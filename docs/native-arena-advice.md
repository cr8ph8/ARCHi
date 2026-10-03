# Hampton move advice in Arena

ARCHi now consumes resolved solo practice observations to suggest a move. The native app reuses Hampton's bounded quotient update, intelligence-force and effective-delta coupling implementation. **Track this suggestion** freezes the recommendation before the next input. A matching observation can then be linked to that exact suggestion.

This is a session-only native consumer. Unity still owns game rules and receives explicit player input. No provider request, model training, persistent profile change, skill certification or companion growth occurs.

## Use it

1. Open **Arena → Play Arena**, and make a solo move.
2. Return to ARCHi. **Practice outcomes → Try a move together** shows a suggestion after the last observed round.
3. Inspect **Why this suggestion** for scores and sample counts. An unobserved move is a neutral prior.
4. Choose **Track this suggestion**, return to the same Arena bout and play a move.
5. Return to ARCHi. The record says whether the next observed input matched, used a different move, or could not be linked.
6. **Save practice report…** exports the retained observations and the tracked suggestion, including its numerical steps. Ending the session clears the in-app record.

The current Unity stream has no active-bout cursor before an input. A reset may therefore be invisible until another action resolves. The UI deliberately says **after observed round**, not that a move is currently legal. A changed bout/state, missing next action, stale connection, changed mode or ended session cannot acquire a successful link. A transient acknowledgment gap keeps only the frozen pending suggestion within the existing five-second freshness bound; it admits no outcome until the ordinary acknowledgment and snapshot validation pass. Automatic native move dispatch requires a separate current-context/command contract.

## Operational definition and equations

These are three Arena-specific exchange coordinates, not the document retain/expand/repair lanes, human traits, or a universal intelligence score:

\[
q=(q_{pulse},q_{guard},q_{signature}),\qquad q_0=(.5,.5,.5).
\]

For an observed move k, let d and t be the **actual** rival and player integrity decreases. Unlike raw damage, they exclude damage beyond the remaining integrity. The authored target is

\[
y=.5+(d-t)/20\in[0,1].
\]

Only target coordinate k changes. With L=P=G=I, force gain .25, learning rate .25:

\[
F=-.25(q-q^*),\qquad \Delta q_{requested}=.25(LI_{obs}-E+F).
\]

Here I_obs is zero except y at k, E is zero except q_k, and q* equals q with q*_k=y. The existing numerical engine norm-caps the requested delta at .125, projects the complete candidate into [0,1]^3, and tries at most twelve halvings. Its fixed per-observation quadratic potential must not increase. The full effective delta, after clipping/backtracking, drives

\[
\Delta s=M^\top(q'-q),\qquad M=.5I,\quad \|M\|_2=.5.
\]

Scores start at .5. The diagonal coupling transfers no evidence to another move. Shield absorption and terminal results remain separate explanatory measures instead of rewarding the same exchange twice. Highest score ranks first; ties use Guard, Pulse, Signature. Signature is excluded if the last observed Spark is zero. Terminal observations offer no suggestion.

Replay is deterministic over at most 32 retained actions in sequence order, using the latest observed field (Guardian or Scout). A redraw does not learn twice. Retirement can change scores because the window is rebuilt from neutral values; this is explicitly bounded memory, not lifetime learning. Gains, target and coupling are authored configuration, not learned causal parameters.

## Attribution and export

One pending suggestion is owned by `UnityPresentationConnection`. It binds its version, session, base action/bout/round, evidence digest, preparation time, coordinate updates and ordered scores. Only the exact next sequence and round can link, with the same bout/field and before-integrity/Spark equal to the base action's after-state. The action must occur after preparation. A different chosen move receives `differentAction`, never `matched`.

Schema 2 of `ArenaPracticeReport` adds optional `adviceTracking`. Its Date-typed `preparedAt` follows Foundation Codable (seconds since 2001-01-01 UTC); fields ending in `Unix` use seconds since 1970-01-01 UTC. It carries the frozen suggestion and resolved or unlinked status. The profile origin digest is not exported; session binding uses a session-salted digest. Scores are not win probabilities. Matching establishes an attributable observation, not that the advice caused the input or improved the outcome.

## Source and evidence boundaries

The adapter reuses [HamptonNumericalDynamics](../desktop/Sources/ARCHiDesktop/HamptonNumericalDynamics.swift), whose source binding is documented in [native numerical adaptation](native-numerical-adaptation.md). It follows the domain-adapter pattern of [HamptonDocumentNumericalControl](../desktop/Sources/ARCHiDesktop/HamptonDocumentNumericalControl.swift), with distinct Arena coordinates and a diagonal coupling. [HamptonArenaAdvice](../desktop/Sources/ARCHiDesktop/HamptonArenaAdvice.swift) declares this new domain mapping; it is not represented as a recovered patent equation.

Per-observation potential decrease does not prove global convergence under changing targets, causal move superiority, general learning, or validation of Hampton's whole stack or patent claims. Current delivery evidence is retained in [the increment result](../output/arena-advice-2026-09-27/RESULT.md). Paired play, live-bout command dispatch and physics contacts remain outside this consumer.


## Delivery observation

Nineteen focused cases passed. The installed walkthrough froze a Pulse suggestion at score 0.5078125 from one observed exchange, preserved it through the player handoff, and linked the next manually chosen Pulse to 7 damage dealt and 10 taken. The native Save sheet wrote the complete two-action schema-2 report, which was inspected on disk; ending the session cleared the in-app summary and advice. No model calls, puzzles or saved growth were involved. These are mechanism and attribution observations, not a gameplay-improvement result.
