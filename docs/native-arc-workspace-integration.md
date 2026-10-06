# ARC Lab workspace integration

18 September 2026. ARCHi means **ARC Hampton Interphase**. This increment connects the existing native ARC solver, evidence shelf, Usage journal and Activity map. It also gives ARC Lab separate solving and saved-result pages. The solver language and independent checker are unchanged.

## Follow a result

1. Open **ARC Lab** from Home or the workspace navigation. **Load sample** loads a synthetic task; it does not start a run. **Import ARC task…** accepts a standard local ARC JSON task.
2. Inspect the training examples, then choose **Solve locally**. **Stop** retires the active attempt. Proposed output and the independent check appear together, with source status and missing or incorrect answers visible.
3. Choose **Usage** on the current result to select that exact attempt. **Activity map** opens its retained evidence node. Selecting an accounting node opens the original retained attempt in Usage.
4. **Saved results** contains retained evidence. **Run again** performs a new solve and compares its result and trace with the retained run. Its current result links to the new attempt; the saved card continues to link to the original attempt.

Training grids, test inputs and proposed predictions have accessible numeric rows as well as color. Evidence hashes and implementation details sit behind disclosures. The compact native layout has light and dark presentation checks. Returning while a solve is active prioritizes the solver page; entering Solve clears old saved-record focus.

## Exact routes and existing owners

| Surface | Identity and behavior |
| --- | --- |
| Current ARC result | The transient review carries the actual application task ID for that attempt. Usage selects it exactly. |
| Saved result | Retains its original task ID and evidence ID. A repeated solve may share the same evidence record while retaining a separate accounting task. |
| Usage | Shows the recent twenty tasks plus an exact older selected task when needed. Missing targets show a notice and clear the old selection. |
| Usage → ARC | Requires current-profile evidence, matching checked outcome and either the retained original task or the current live review's matching task. A matching hash in the account-wide journal alone is insufficient. |
| Activity map | Selects the exact evidence node. Its accounting route carries an explicit task ID. Opening the graph projects existing records without dispatching or saving work. |

The conservative reverse-link rule means an older duplicate attempt can remain visible in Usage without an **Open ARC result** button after its live review expires. The journal is shared across profiles; a content hash does not establish which profile owns that attempt.

[CompanionStore](../desktop/Sources/ARCHiDesktop/CompanionStore.swift) coordinates transient navigation. [ARCCapabilitiesStore](../desktop/Sources/ARCHiDesktop/ARCCapabilitiesStore.swift) owns retained ARC evidence, and [TokenStewardWorkspace](../desktop/Sources/ARCHiDesktop/TokenStewardWorkspace.swift) presents the existing journal. No storage schema, model dispatch, spending guard, profile migration or companion development rule changes here.

## What the result means

A predicted grid is a proposal. A training fit or matching rerun does not establish a correct test answer. Checker counts use any supplied targets, and imported source provenance remains unverified. Synthetic samples are labeled and do not establish a benchmark score.

**Cell work** is a deterministic abstract search budget. Elapsed milliseconds describe the observed run; CPU and energy cost remain unmeasured. No model request occurs during local symbolic solving. Opening evidence does not turn a checked answer into user-marked usefulness or grant memory, permissions or Seed growth.

This integration does not expand the fixed 174-candidate v3 solver, qualify interactive ARC3 or reproduce the full Hampton/Q2E architecture. Historical v2 replay keeps its 170-candidate catalog. No official ARC evaluation or current v4 discovery-report result is established.

## Dated local checks and delivery state

On 18 September 2026, the focused native run executed **146 tests, with three skips and no failures**. The three Home presentation cases require their separate opt-in native environment. Seven routing tests cover exact joins, unchanged owner data, profile boundaries, unreadable and missing targets, replay attempt identity, and selection beyond the recent twenty. See [ARCWorkspaceRoutingTests](../desktop/Tests/ARCHiDesktopTests/ARCWorkspaceRoutingTests.swift).

One separate [native presentation test](../desktop/Tests/ARCHiDesktopTests/ARCSolverPresentationTests.swift) passed in a disposable window with an 880×640 viewport and navigation width reserved. It exercised sample loading, accessible training rows, local solve, exact Usage/evidence callback IDs, Saved results, rerun with a different accounting task, and light/dark captures. This fixture checks the callbacks; it does not itself establish an installed Usage or Activity map visit. These are bounded local observations, not the full desktop acceptance suite. Earlier failed build/navigation runs are retained separately.

The installed app was also exercised on 18 September 2026: **Home → ARC Lab → Load sample → Solve locally** produced a synthetic result checked exact 1/1, with 174 candidate attempts, nine training fits and 14,946 abstract cell-work units. The dark Activity map displayed the exact selected evidence and its original accounting task; that inspector showed 50 ms end-to-end and explicitly unmeasured CPU/energy cost. Strict app and Unity-helper signatures passed. Four observed saved profile/registry files and the Unity-helper executable retained their exact hashes.

Installed acceptance remains **partial**. The computer-use inspection service repeatedly crashed with an `EXC_BREAKPOINT` at `Array.remove(at:)` and closed its pipe during navigation. Installed Usage focus, its reverse **Open ARC result** click, and visual scrolling to a task older than the recent twenty remain unverified. The routing tests and disposable callback checks do not close those gaps. This service failure does not establish an application defect or a passing route.

The final native presentation rerun passed after a contrast adjustment; the earlier captures and failed build/navigation logs remain retained. These tests and installed observations describe one local Mac, not the full desktop acceptance suite. Public artwork distribution and acceptance of the exact exported artifact remain open. The existing GitHub draft is a separate source-review checkpoint; its delivery receipt belongs to the release record. A draft does not declare Beta approval, a merged release or a notarized binary release. Full VoiceOver, ordinary-day and second-Mac acceptance remain separate work.
