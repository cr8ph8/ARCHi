# Arena practice reports

27 September 2026 · native ARCHi integration

**Arena → Play Arena → Practice outcomes** turns the existing checked solo-action stream into an inspectable summary. It shows action counts, damage dealt/taken, shield absorption and observed terminal results. These metrics describe the retained actions only; they do not measure companion intelligence or learning.

Use **Save practice report…** before ending practice to export a frozen JSON snapshot. Saving uses an explicit destination, includes the original action/bout IDs and observation time, and excludes companion identity, origin digest, notes and model context. No new persistent profile store is created. Cancelling saves nothing. If the original session ends while the save panel is open, export fails rather than silently substituting the next session.

## Coverage is part of the result

The consumer keeps at most 32 observed actions. Each report includes:

- **Retained:** the actions whose records and metrics are in this export.
- **Missed:** sequence positions never received between polls.
- **Retired:** previously observed actions that aged out of the 32-action window.
- The consumed sequence, presentation revision, checked snapshot time, export-capture time and current mode.

Repeated polls do not add another action. A terminal result is counted once per retained bout. A win whose ending action is outside the window is not counted. An empty stream supplies no report. Earlier accepted solo observations can remain visible if the connection becomes stale or switches to paired play; their original timestamp and mode are retained. A save never establishes that the connection is currently live.

These are locally consistency-checked Unity rule outcomes from explicit player inputs. They are not independently authenticated results, physics-contact evidence, autonomous actions, paired-game receipts, remote multiplayer, model learning or canonical growth. The native profile retains authority over identity and development. The Unity player and existing combat rules are unchanged by this native reporting increment.

Schema 2 also exports an optional frozen Hampton move suggestion and its observed link. The [Arena advice guide](native-arena-advice.md) defines the target, update, ranking and strict attribution rules. Saving now uses an attached sheet so Arena observation can continue while the destination is chosen.

## Investor use

Show a few actual solo actions, return to ARCHi, match those actions to their sequences and outcomes, and save the report. Present the coverage and limits alongside the numbers. Keep the running build identifier with the demonstration. Use the [investor walkthrough](investor-evidence-walkthrough.md) to relate this observation path to separately evidenced everyday method learning and numerical adaptation.

Source: [report projection](../desktop/Sources/ARCHiDesktop/ArenaPracticeReport.swift), [connection owner](../desktop/Sources/ARCHiDesktop/UnityPresentationConnection.swift), [native panel](../desktop/Sources/ARCHiDesktop/WorldOutcomeCard.swift). Verification and installed status are recorded in the [current progress report](system-progress-2026-09-26.md).

## Current verification

The earlier reporting increment passed eight focused projection/owner cases and observed two actual solo inputs: 7 total damage dealt, 9 taken and 7 blocked. A follow-through on 27 September observed these same values in the populated native summary and confirmed that ending the session cleared it. That closes the earlier populated-summary gap without rewriting its historical receipt.

The old modal Save panel still stalled during the follow-through. The current increment replaces it with a workspace-owned attached sheet and adds native advice. Nineteen focused cases passed; the final installed walkthrough completed suggestion tracking, a matched next action, native Save, and cleanup. The saved schema-2 JSON was checked against the observed actions. Detailed delivery evidence is recorded in [the increment result](../output/arena-advice-2026-09-27/RESULT.md). This remains development-alpha evidence, not owner/investor-demo acceptance.
