# Contextual memory influence

28 October 2026 · source integration candidate

This change connects explicitly authored attraction/detraction assessments to two existing decision surfaces. It extends their existing persistence owners. It does not change model weights, model activations, factual review status or execution permissions.

## Implemented surfaces

| Surface | Memory source | Target and effect |
| --- | --- | --- |
| Native ARCHi | An existing, current kept lesson with its exact snapshot binding | An exact saved document-method version. Signed influence refines suggestions within groups with equal reviewed outcome quality, after the existing resource-based order. |
| Retained QiMon practice | A recruited QiMon's kept Journey origin or eligible later practice event | A legal rules-v1 practice action. The player sees a ranked suggestion and can explicitly fill the move selector; playing/sealing a move remains separate. |

The native Memory map's **Manage memories** route reaches the existing kept-lesson controls. This first integration does not assign assessments to every graph record: source copies, knowledge pages, receipts and presentation particles retain their own types and owners.

The separately authored **QiMon First Signal** chapter is not in this source distribution. `QiMonEmbeddedGame` hosts a separately selected/bundled `QiMonFirstSignalWeb` build. Updating retained practice code does not modify that chapter or its save. No new host bridge exports native private memory to the chapter.

## Use in native ARCHi

1. Open the existing memory manager and a kept lesson.
2. Choose **Edit method influence…** and an exact saved method version.
3. Set direction, magnitude, assessed confidence and retrieval salience.
4. Choose **Save influence**. **Remove relationship** withdraws the assessment.
5. In passage revision, inspect the current saved influence and method ordering. Choose a method through the existing preview/preparation flow; Send, checks, Apply and outcome review remain explicit.

The lesson still has to match its current topic/task, exact source and expiry restrictions. A relation may be retained without contributing to the current question. Attraction never makes an unavailable or withdrawn method eligible. Zero magnitude or confidence removes the signed contribution without changing the source's retrieval eligibility.

No assessment is inferred from selection, hover, animation, repeated retrieval, a model reply or a successful mechanical check. The confidence control is the user's assessment, not calibrated model certainty.

### Native ownership and migration

`NativePreferenceDocument` version 11 adds optional `memoryInfluences` in the same bounded preference file. Each record binds an `EvolutionLessonUse` (lesson ID, content revision and snapshot digest) to an exact `DocumentProcedureUse`, plus the contextual assessment. The existing 64 KiB envelope limit remains; there are at most 64 relationships overall and 16 per lesson.

Changing an assessment advances the preference envelope revision. It leaves the original lesson, its content revision, its snapshot digest, and methods derived from that snapshot intact. This separation prevents a polarity change from making its own evidence appear rewritten. Repeating an identical save is a no-op. Changing the lesson's content or withdrawing it clears its relationships in the same owner transaction; a changed method version is never silently substituted as the target.

Known preference versions 2–10 migrate in memory through the existing loader. Loading does not rewrite the saved bytes. Only an explicit successful owner write saves v11. The current exact disk baseline and editor revision are checked before persistence. Older application binaries do not understand v11; an application rollback must use the existing corresponding profile recovery workflow rather than manually relabeling the schema.

The relation is ranking metadata, not additional model context. Captured provider lesson snapshots remain byte-identical when only an assessment changes. Existing source, cancellation, correction, recovery and domain checks still govern their use.

Several copied lessons from one exact source or generating request count at most once for a candidate, using the existing retained lesson order. Their separate records remain inspectable. The pure evaluator rejects duplicate eligible source/origin inputs; the owner constructs the canonical independent input set.

## Use in retained QiMon practice

1. In **Your QiMon**, invite a recruit from an eligible kept Field trace.
2. Open its **Memory influence** controls and choose a source memory and rules-v1 action.
3. Choose **Keep this assessment** to append through the existing roster owner.
4. Start **Practice selected**. Inspect each legal move's base score, signed influence and retrieved source weights.
5. **Use suggestion** fills a current legal choice. It does not play a turn, seal a command, save a battle or award training.

Set the relationship to **Unassessed** to withdraw directional guidance. Each source/member/context/action has one current assessment projected from its retained edit history. An opposite assessment replaces the current projected contribution; repeated edits do not add evidence votes.

### QiMon ownership and migration

Journey events remain unchanged. Assessments are explicit events in the existing QiMon roster journal, bound to a current source event ID and SHA-256 digest. Roster and Journey revisions are rechecked by the existing writer, and every projection validates its retained source authority. Stale, changed, foreign or missing sources cannot supply a recommendation.

Existing version-1 rosters and archives retain their exact format until the first explicit assessment. That edit opts the roster/archive into version 2; old events remain byte-for-byte unchanged. New archives advertise their version instead of disguising the new action as v1.

The journal remains bounded at 256 events. Version 2 reserves one future event per currently assessed relation, so every relation can still be set to unassessed at the capacity boundary. Other roster actions cannot consume those reserved withdrawal slots. Magnitude zero and assessed neutrality are still assessed states; an explicit unassessment releases the reservation.

The practice policy supplies the unmodified baseline recommendation. A matching baseline move receives 0.25 arbitrary ranking units and other legal moves receive zero. Contextual influence is added to those units. With no assessed evidence, the original baseline recommendation remains first. These values are a suggestion heuristic, not a win probability or a change to damage, game rules or character identity.

## Calculation contract

For an eligible memory:

```text
retrieval r = contextMatch × retrievalSalience
weight w = r × assessedConfidence × magnitude
influence I = Σ(w × polarity) / (1 + Σw)
```

Polarity is `+1` (attraction), `−1` (detraction), `0` (assessed neutral), or null (unassessed). Context match, salience, magnitude and assessed confidence are independently bounded to [0,1]. Nonfinite values and malformed source/target identities are rejected.

Unassessed relations have zero influence weight while retaining their eligible retrieval value. Neutral relations add denominator weight and no directional numerator. Positive, negative and neutral masses remain separate, making cancellation distinguishable from absent assessment. The unit prior keeps weak evidence weak; influence stays within (−1,1) for finite bounded inputs.

Current production callers use context match 1 only after the existing exact context/source eligibility checks. This is not a learned similarity score. Salience weights an already eligible memory in this assessment; it does not alter the native lesson's general topic matcher or provider context. Neither the score nor node geometry grants permission to execute a candidate.

## Source and validation

This candidate builds on `codex/unified-orb-20261028` at `7a4d36dbeb9b74bc9f1f097de9c5b13227d46f57`. That baseline's native CI reported a Swift SIMD type-check timeout in `LiminalSurfaceLight`. A small typed-intermediate refactor preserves the operation order and removes that compilation obstacle; it does not introduce memory-driven geometry.

Focused checks are executable through `.github/workflows/memory-influence-validation.yml`:

```sh
npx vitest run src/qimon-memory-influence.test.ts src/qimon-roster.test.ts src/qimon-relay.test.ts src/battle-engine.test.ts src/journey-activity.test.ts
npm run build
node scripts/memory-influence-playtest.mjs
swift test --package-path desktop --filter 'ContextualMemoryInfluenceTests|MemoryInfluenceIntegrationTests|KeptLessonsTests|LessonStoreTests|KeptLessonRequestTests|CoreMemoryFreshnessTests|HamptonMethodOutcomesTests|HamptonMethodResourceOutcomesTests|ReadingCorrectionMemoryTests|LiminalSurfaceLightTests/testExpression'
```

Native tests use synthetic source, lesson, method and preference owners. They cover sign reversal with unchanged retrieval and source content, same-source method provenance, persistence/reload, version migration without rewrite, no-op saves, stale writers, exact-target isolation, source expiry/withdrawal, export/recovery and invalid metadata. QiMon tests exercise current roster persistence, real legal recommendation changes, legacy round trips, source/digest validation and reserved withdrawal capacity. The browser playtest uses an installed Chrome (or `PLAYWRIGHT_CHROMIUM_EXECUTABLE`) and disposable synthetic storage; its screenshots and report go to `PLAYTEST_OUTPUT_DIR` or a temporary directory. These checks establish implementation behavior, not measured task-quality gains or scientific validation of a universal memory model.

### Authoring and installation boundary

Apply the focused change through the existing authored-source workflow. Reconcile it into the current authoring workspace; do not replace that workspace with this curated distribution tree. Run the affected native checks and the existing guarded desktop build/install process using its qualified resources. Preserve the separate First Signal build and game save.

The source candidate alone is not an installed application. Actual installation requires the authoring Mac, its current source and qualified bundled resources. First Signal gameplay integration additionally requires that chapter's actual source and save owner. No app installation, private profile access, live-provider call, Unity build or device update is performed by the CI workflow.
