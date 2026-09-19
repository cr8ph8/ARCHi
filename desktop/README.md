# ARCHi native desktop Alpha candidate

**ARCHi — ARC Hampton Interphase.** This is the ARCHi companion app, a separate product from Quotient Wiki OS. Its interface centers the active companion, conversation, shared work and chosen memories. KIN and other chosen companion names identify the individual within ARCHi; they do not rename the application. See the [interface identity](../docs/archi-interface-identity.md) for the reference direction and product boundary.

The current target is a supervised local desktop Alpha on this Mac. Start with the [desktop Alpha guide](../docs/desktop-alpha-guide.md) for the task checklist, explicit save/load behavior and recovery. Candidate verification remains recorded separately in the [current plan](../docs/archi-qimon-build-plan.md) and [status](../docs/local-alpha-status.md); this README does not declare release acceptance.

## Build and launch

Building requires macOS 14+ and Xcode's Swift toolchain. The Swift package has no external package dependencies. Local Qwen assistance needs installed Ollama and a supported installed model; ARCHi starts or reuses that local runtime automatically. The companion and local ARC solver run without a model connection. See [Native Qwen and bounded fallback](../docs/native-qwen.md).

Export any working draft, keep the choices you want to retain, and **Quit ARCHi through its menu**. From the repository root:

```sh
./script/build_and_run.sh
```

The script updates the single `/Applications/ARCHi.app`, preserving the existing Review bundle identifier and profile ownership. `--review` is a compatibility alias; it does not create another personal app. The script retains the installed Unity helper, or requires `--unity-player /path/to/qualified-player.app` for a first installation. It refuses to replace any running ARCHi session and preserves the previous bundle for recovery.

Use `--stage-only --stage-dir /private/tmp/unique-candidate-directory` to build a candidate without replacing or launching the installed app. Generated build products use `/private/tmp/archi-desktop-build-<user-id>`; `ARCHI_BUILD_SCRATCH_PATH` can select another scratch directory. `--verify` also runs the native test suite. These locally signed builds are not notarized distribution releases. Reopen the installed app normally instead of rebuilding just to open it.

## Current native experience

- **ARC → Interactive ARC3** discovers an installed offline runtime, displays its actual frames, accepts manual actions and explores in batches of up to eight actions. Chat and the Seed bubble expose `/arc3 open`, `/arc3 explore` and `/arc3 stop`. Episodes retain proposed actions, observed outcomes and task-local transition evidence, with Usage and Activity map links. This first explorer uses no model calls; goal-directed model planning remains future work. [Setup and scope](../docs/active-arc3.md).

- **Capability checks → Solve an ARC task locally** imports standard train/test JSON or loads a synthetic sample, runs a bounded rule search, independently checks predictions and retains traces with Usage/activity graph links. [Scope and operation](../docs/native-arc-solving.md).

- **ARCHi Home** opens the companion's field interface with dark surfaces, cyan accents and the current companion appearance. Its connection, shared document, active kept lessons, Node Lab records and personal rhythm come from the existing app state. Each action opens its existing destination. Use Window → ARCHi Home (Command–0) to return. The native window retains its 880 × 640 minimum, with scrolling at smaller sizes and grouped panels in wider windows.

- **Assistant** defaults to ARCHi-managed local Qwen, with one Codex fallback for an eligible connection, generation or timeout failure. Local-only auto-connect and manual routes remain available; the chosen route survives restart. Preparation sends no draft or document. Send captures the question, shared copy, selected passage and reply settings; kept lessons, personal context and local conversation never enter fallback. A desktop snapshot requires its own exact-copy permission for external use. Stop cancels owned work.
- **Work together** holds a UTF-8 working copy with exact passage selection, placement preview, Explain/Rewrite/Shorten, Before/After review, checked Apply, one-step Undo and separate draft export. The imported original is unchanged. The working copy and Undo are session-only: **Export before Quit, Change document or Stop sharing**.
- **What I remember** keeps explicitly authored lessons, with inspect/revise/withdraw/export controls. Eligible lessons go only to local Qwen. Temporary session context is separate, off by default, and consumes optional selection/reminder calls only when eligible input exists. Neither feature trains model weights.
- **Companion room and Arena** use the bundled Unity renderer under the native session owner. Arena currently supports local practice and two seats on one Mac; online multiplayer and canonical rewards remain unimplemented.
- **One individual, familiar Pearl.** The current Pearl receives subtle individual visual variation automatically from the existing Journey when it is available. Appearance has no work, role or battle quota. An explicit shape choice can change the body; it does not rewrite recorded history or create another individual. The current visual variation is not proof of learned physical development. Original and the other starter choices remain available.
- **Appearance, Evolution and Personal rhythm** retain explicit choices. Save appearance/rhythm in What I remember. Save evolution separately; after a new launch, use Load saved to restore saved Evolution choices and appearance. There is no automatic Evolution load.
- **Connections → Reactor** offers an optional local expression preview and separately reviewed API trial. Local artwork remains the fallback. Blender authors visual assets; the bundled Unity player presents Companion and Arena while native ARCHi retains identity and memory. The Unity editor is not required to use the installed player.

ARCHi's actual native position remains authoritative. Moving or hiding him, scrolling the source or changing the selected passage invalidates affected spatial references. Recover a hidden companion with the menu-bar sparkles icon or Window → Show companion. Closing the workspace leaves the app running; Quit ends it through the normal cleanup path.

## Evidence and remaining qualification

The [personal assistance checkpoint](../docs/native-personal-assistance.md) records bounded local-model and native editing/lesson evidence. [Practice and Evolution](../docs/battle-evolution-checkpoint.md), [individual appearance](../docs/individual-appearance-checkpoint.md), and [Reactor expression](../docs/native-reactor-expression.md) retain their exact dates, build identities and limits. Historical test totals are not results for a newly built candidate.

The [Alpha guide](../docs/desktop-alpha-guide.md) defines a short supervised same-Mac check. Broader ordinary-day reliability, complete recovery, accessibility, fresh-Mac setup and distribution qualification remain in the existing plan. Live Reactor likeness/termination, full ARC or teacher/student training, external-application editing, mobile, camera/AR and trading are not included in this Alpha acceptance claim.

### Document work integration

Selected-passage revision now binds explicit requirements at Send, checks proposed edits, and retains metadata for Apply/Undo. See [active document work](../docs/active-document-work.md) for its use, source constraints and Hampton learning priorities.

After Apply, mark the retained result **Helpful** or **Needs correction**, or withdraw an earlier review. Usage reconciles the exact review event. **Add to learning review** and **Save evolution** are separate choices; writing a correction opens Memory and requires explicit **Keep**. Only the exact still-kept lesson version cited by the original local request is eligible for lesson-use confirmation. These choices do not automatically change your Seed or train model weights.

An interrupted Undo still permits syncing or withdrawing an existing review, but cannot add new positive learning. An unreadable review history blocks loading saved learning until repaired. Existing unfinished lesson drafts are preserved. Reviewed records are retained within the 64-record journal limit; a full history can block new work until explicit history management is added.

## Reviewed document procedures

After a helpful applied edit, explicitly write and Keep a procedure. Use it for a later selected passage with matching requirements, then review the fresh result. Exact version references and retained counterexamples prevent corrected or withdrawn methods from silently returning. See [operation, retention and limits](../docs/native-document-procedures.md).

## Revise a saved method

In Work together, open Saved procedures and choose Edit method. Save a new candidate version with an explicit change note and helpful applied support; earlier versions and request bindings remain in history. A blocked method requires later corrective work. Only the latest version is offered for new preparation. See [document procedures](../docs/native-document-procedures.md) for retention and v1/v2 archive compatibility.

## Teach an activity

Work together now offers Teach this activity. Keep a lesson for Chat, Reading documents, Revising passages, or a matching topic phrase. Source restrictions and expiry still apply. Saved methods are ordered by matching requirements and their own version’s recorded helpful/correction outcomes. See [task memory and outcomes](../docs/native-task-memory-outcomes.md).

## Shared Q2E work control

Document revision and ARC3 planning now use one versioned native controller. Existing observations and reviewed outcomes select reuse, an alternative, correction or pause. Work together offers Prepare next step; local Qwen receives the captured approach on Send. ARC3 plans up to eight actions, observes and replans, retaining its decisions and outcomes. See [native Q2E control](../docs/native-q2e-control.md) for coordinates, feedback and bounds.

## Read with context

Open a document or meeting notes in Work together, write a question and choose Find relevant passages. Local Qwen uses a bounded section plan with exact source ranges. The preview identifies omitted coverage. After a completed local answer, Helpful or Needs correction feeds the next reading approach for that source. The same reply controls are available in Chat and the Seed bubble. See [native document reading](../docs/native-document-reading.md).
