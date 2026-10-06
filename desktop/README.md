# ARCHi native desktop Alpha candidate

> Publication note: references marked “local reference” are intentionally omitted from this curated snapshot. Their authored documents and receipts remain preserved in the main workspace; this page does not reproduce their evidence.

**ARCHi — ARC Hampton Interphase.** This is the ARCHi companion app, a separate product from Quotient Wiki OS. Its interface centers the active companion, conversation, shared work and chosen memories. KIN and other chosen companion names identify the individual within ARCHi; they do not rename the application. See the interface identity (local reference) for the reference direction and product boundary.

The current target is a supervised local desktop Alpha on this Mac. Start with the desktop Alpha guide (local reference) for the task checklist, explicit save/load behavior and recovery. The [2 October native memory workspace delivery](../docs/native-memory-dashboard.md) records that dated installed increment and limits, following the separate [method-memory delivery](../docs/method-memory-integration-2026-10-02.md) earlier that day. The [29 September system status](../docs/system-status-2026-09-29.md) is retained historical scope; this README does not declare release acceptance.

The [3 October living-memory flow](../docs/knowledge-particle-body-and-ar.md#3-october--one-living-memory-canvas) adds shared Seed/map/Liminal controls and explicit record-note previews. That dated installed walkthrough exposed a native renderer issue; its receipt records the corrective candidate and pending visible-window qualification at that time. See its historical delivery status (local reference).

The particle-first native map is installed. Its build and 15 focused checks passed, followed by installed particle selection, source inspection, focus and local-context attachment checks. Full-size visual acceptance remains partial.

The installed update adds typed record states, directed relationship inspection and saved-method evidence. Its [delivery receipt](../docs/accountability/evidence/r02-native-memory-meaning-2026-10-02.json) records 42 unique focused checks passing and installed relationship/rationale readback; the observations above describe the preceding particle delivery.

The latest [native method workflow](../docs/native-memory-dashboard.md#from-a-concept-to-useful-work) connects reviewed concepts to authored methods, exact-version document preparation and retained use evidence. Its [receipt](../docs/accountability/evidence/r02-native-memory-method-flow-2026-10-02.json) records 21 unique focused checks and one real local Qwen use. Mechanical checks passed, but attribution detail was omitted; no edit or Helpful review was accepted. This is usable workflow integration, with successful method transfer still unestablished.

## Build and launch

For model configuration without opening the interface, see locked-screen maintenance (local reference). The prepared executable can inspect saved model settings or queue a verified local-model change for its next native launch. This leaves the currently running companion session intact.

Building requires macOS 14+ and Xcode's Swift toolchain. The Swift package uses the existing local `shared/ARCHiSpatial` package and has no remote SwiftPM dependencies. Local Qwen assistance needs installed Ollama and a supported installed model; ARCHi starts or reuses that local runtime automatically. The companion and local ARC solver run without a model connection. See [Native Qwen and bounded fallback](../docs/native-qwen.md).

Export any working draft, keep the choices you want to retain, and **Quit ARCHi through its menu**. From the repository root:

```sh
./script/build_and_run.sh
```

The script updates the single `/Applications/ARCHi.app`, preserving the existing Review bundle identifier and profile ownership. `--review` is a compatibility alias; it does not create another personal app. The script retains the installed Unity helper, or requires `--unity-player /path/to/qualified-player.app` for a first installation. It refuses to replace any running ARCHi session and preserves the previous bundle for recovery. Normal updates now keep rollback bundles in `~/Library/Application Support/ARCHiRecovery/Rollbacks`, outside Applications. See [one-app operation and recovery](../docs/one-app-system.md).

Use `--stage-only --stage-dir /private/tmp/unique-candidate-directory` to build a candidate without replacing or launching the installed app. Generated build products use `/private/tmp/archi-desktop-build-<user-id>`; `ARCHI_BUILD_SCRATCH_PATH` can select another scratch directory. `--verify` also runs the native test suite. These locally signed builds are not notarized distribution releases. Reopen the installed app normally instead of rebuilding just to open it.

The 5 October packaging change records a unique candidate UUID, a numeric `CFBundleVersion`, native/local-dependency source hashes and packaged payload hashes in `Contents/Resources/ARCHiBuildIdentity.json`. Dirty and untracked native inputs are included; changed before/after inputs stop promotion. The payload identity precedes outer signing, so it is not the final signed bundle hash, a hermetic-build proof or runtime acceptance. The fixture checks use a simulated compiler/signer. Later on 5 October, real Swift compilation, stage packaging and strict/deep signing passed for candidate `e230294b-e5ad-4932-bdf7-65ef32c7efc6`, build `356.65.66`. Its external signed manifest was retained before removing the temporary candidate. Nothing was installed or launched; populated workflow and visible performance acceptance remain open. See the executed reconciliation (local reference). Existing install, normal-Quit and rollback guards remain in place; no archives are pruned automatically.

## Current native experience

- **Memory map** opens at startup and leads the sidebar's Everyday group. Explore actual retained sources, authored pages, kept lessons and saved methods. Focus direct connections, follow a related node, and use Back to return; search/type filtering preserves remaining node positions in the card layouts. Ask ARCHi opens the same native question workspace beside the map. **Ask about this** explicitly attaches an exact current reviewed page for local chat; selecting a node sends and attaches nothing. Drafts survive closing/reopening the pane. Showcase, All activity and Home remain available. [Guide and limits](../docs/native-memory-dashboard.md).

- **Particle memory workspace.** Particles is the default, with stable record anchors, bounded artistic motes and focus framing that stays fixed through search/type filtering. The companion core shares its existing runtime light expression; exact pages prepared for the next local reply carry a dashed ring and explicit label. Motion pauses while hidden, inactive or reduced motion is requested. Motes and glow add no records, inferred links, learning credit or model calls. Retained memory supplies identity and exact context; activity supplies expression, while Hampton outcomes and quotient coordinates stay with their existing owners. [Mapping and limits](../docs/native-memory-dashboard.md#particles-memory-and-activity).

- **One living-memory canvas.** With the qualified Liminal package, Seed, Memory map and Liminal · QiMon share one mounted Metal surface and one continuous form control. A selected record retains its exact ID and inspector through the transition. The Seed uses retained artwork with mapped record particles; the Beast uses its authenticated point frame. Select a record and open **Sound & signal** to audition its type's note, subject to existing musical-cue and Quiet preferences. Brainwave names are explicit artistic associations, not sensor readings. [Mechanism, Blender lineage and limits](../docs/knowledge-particle-body-and-ar.md#3-october--one-living-memory-canvas) · Delivery evidence (local reference).

- **Typed meaning and method evidence — installed, focused checks passed.** Owner-derived states distinguish reviewed pages, drafts, withdrawal and unavailable or stale evidence. Connection inspection shows source, relationship and target, retaining exact reviewed declaration versions, rationale and references. Particle line patterns supplement relationship text and symbols. Saved methods separate preparation, retained dispatch evidence, checks, current owner review and counterexamples, with up to three recent exact-version uses and any valid captured Hampton decision. Missing evidence stays explicit; none of this creates a new store, model request, learned capability or companion state change. [Behavior and boundaries](../docs/native-memory-dashboard.md#relationship-meaning-and-method-evidence).

- **Work from memory.** Select a current reviewed Concept → Create a method → Inspect this method version → Try in document work. Select a passage there and preview the exact method before Send. The map's Work popover reuses the outcome, review and procedure owners; document work returns to the exact method node. Source changes block Save without removing an authored draft. New methods remain candidates until useful outcomes are established. Leaving document work currently cancels an unapplied proposal; retained evidence records that cancellation, not a review.

- **ARC → Interactive ARC3** discovers an installed offline runtime, displays its actual frames, accepts manual actions and explores in batches of up to eight actions. Chat and the Seed bubble expose `/arc3 open`, `/arc3 explore` and `/arc3 stop`. Episodes retain proposed actions, observed outcomes and task-local transition evidence, with Usage and Activity map links. This first explorer uses no model calls; goal-directed model planning remains future work. [Setup and scope](../docs/active-arc3.md).

- **Capability checks → Solve an ARC task locally** imports standard train/test JSON or loads a synthetic sample, runs a bounded rule search, independently checks predictions and retains traces with Usage/activity graph links. [Scope and operation](../docs/native-arc-solving.md).

- **ARCHi Home** opens the companion's field interface with dark surfaces, cyan accents and the current companion appearance. Its connection, shared document, active kept lessons, Node Lab records and personal rhythm come from the existing app state. Each action opens its existing destination. Use Window → ARCHi Home (Command–0) to return. The native window retains its 880 × 640 minimum, with scrolling at smaller sizes and grouped panels in wider windows.

- **Ask ARCHi** unifies Home, sidebar, menu and bubble conversation entry points. Its companion subtitle preserves the current individual; Memory map and Work together open their existing owners. [Interface and boundaries](../docs/native-ask-archi.md). It starts with Local only when routing preferences are missing or unreadable. Explicitly selecting Local + Codex fallback permits one eligible fallback after a local connection, generation or timeout failure. Manual and external routes remain available; the chosen route survives restart. See [routing and payload boundaries](../docs/native-automatic-assistance.md). Preparation sends no draft or document. Send captures the question, shared copy, selected passage and reply settings; kept lessons, personal context and local conversation never enter fallback. A desktop snapshot requires its own exact-copy permission for external use. Stop cancels owned work.
- **Paste text…** in Work together opens a plain-text draft directly, without the file picker. Text is local and session-only; Send remains separate. Export keeps a copy. Pending pasted drafts block Quit, profile switching and restore; stale source/profile changes and pending voice/proposal work cannot be replaced.
- **Work together** holds a UTF-8 working copy with exact passage selection, placement preview, Explain/Rewrite/Shorten, Before/After review, checked Apply, one-step Undo and separate draft export. The imported original is unchanged. The working copy and Undo are session-only: **Export before Quit, Change document or Stop sharing**.
- **What I remember** keeps explicitly authored lessons, with inspect/revise/withdraw/export controls. Eligible lessons go only to local Qwen. Temporary session context is separate, off by default, and consumes optional selection/reminder calls only when eligible input exists. Neither feature trains model weights.
- **Companion room and Arena** use the bundled Unity renderer under the native session owner. Arena currently supports local practice and two seats on one Mac; online multiplayer and canonical rewards remain unimplemented.
- **One individual, familiar Pearl.** The current Pearl receives subtle individual visual variation automatically from the existing Journey when it is available. Appearance has no work, role or battle quota. An explicit shape choice can change the body; it does not rewrite recorded history or create another individual. The current visual variation is not proof of learned physical development. Original and the other starter choices remain available.
- **Appearance, Evolution and Personal rhythm** retain explicit choices. Save appearance/rhythm in What I remember. Save evolution separately; after a new launch, use Load saved to restore saved Evolution choices and appearance. There is no automatic Evolution load.
- **Connections → Reactor** offers an optional local expression preview and separately reviewed API trial. Local artwork remains the fallback. Blender authors visual assets; the bundled Unity player presents Companion and Arena while native ARCHi retains identity and memory. The Unity editor is not required to use the installed player.

ARCHi's actual native position remains authoritative. Moving or hiding him, scrolling the source or changing the selected passage invalidates affected spatial references. Recover a hidden companion with the menu-bar sparkles icon or Window → Show companion. Closing the workspace leaves the app running; Quit ends it through the normal cleanup path.

## Evidence and remaining qualification

The personal assistance checkpoint (local reference) records bounded local-model and native editing/lesson evidence. Practice and Evolution (local reference), individual appearance (local reference), and Reactor expression (local reference) retain their exact dates, build identities and limits. Historical test totals are not results for a newly built candidate.

The [2 October native workspace receipt](../docs/accountability/evidence/r02-native-memory-workspace-2026-10-02.json) records a passed build and 14 focused checks, guarded installation with rollback, and native accessibility readback of startup, source/version inspection, focus/Back and explicit local-page attachment. The shared draft survived pane close/reopen; nothing was sent and no model call ran. Full-size captures returned a Stage Manager thumbnail, so final visual acceptance remains partial. This desktop increment adds no new chat or memory store and leaves iPhone unchanged.

The same receipt also records the final particle build, 15 focused checks and installed interaction observations. All 22 monitored profile JSON files and 435 resource files remained byte-identical. Measured frame rate, full-size visual acceptance and live expression transitions remain open; this is not full Q2E qualification, a Unity body delivery or an iPhone update.

The earlier typed meaning increment passed 42 unique focused checks, compiled/installed identity verification and strict/deep signing. At that checkpoint all 22 monitored profile files and 435 resources were unchanged and Hampton had no saved methods. The later method-flow delivery adds one explicitly authored concept-origin candidate and one local request. Its 21 unique focused checks passed; native readback verified the source, exact preparation, dispatch, seven mechanical checks, no owner review and captured Hampton controller decision. A full-size candidate-map image was observed; later captures again returned thumbnails. All 435 resources remained unchanged; document-work and Usage records changed intentionally and the method archive was created. No Helpful credit was awarded. The graph digest covers typed metadata while bindings stay stable; Unity's particle export does not acquire evidence prose.

The Canvas particle path requests 15 Hz; the qualified Metal path requests 30 fps. Requested cadence is not measured throughput: sustained performance and installed visual qualification remain open. Useful applied method transfer, a persistent pending-proposal handoff, reverse map-to-body highlighting, broader visual/accessibility acceptance and iPhone/Unity presentation parity remain open alongside existing release blockers. Existing body-to-map navigation and Unity sidecar publication do not establish this broader parity.

The Alpha guide (local reference) defines a short supervised same-Mac check. Broader ordinary-day reliability, complete recovery, accessibility, fresh-Mac setup and distribution qualification remain in the existing plan. Live Reactor likeness/termination, full ARC or teacher/student training, external-application editing, mobile, camera/AR and trading are not included in this Alpha acceptance claim.

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

Document revision, reading and ARC3 planning use the existing versioned native controller. Their numerical adapters share one pure approach policy; admission, coordinates, receipts and replay remain with each domain owner. Existing observations and reviewed outcomes select reuse, an alternative, correction or pause. Work together offers Prepare next step; local Qwen receives the captured approach on Send. ARC3 plans up to eight actions, observes and replans, retaining its decisions and outcomes. See [native Q2E control](../docs/native-q2e-control.md) for coordinates, feedback and bounds.

## Read with context

Open a document or meeting notes in Work together, write a question and choose Find relevant passages. Local Qwen uses a bounded section plan with exact source ranges. The preview identifies omitted coverage. After a completed local answer, Helpful or Needs correction feeds the next reading approach for that source. The same reply controls are available in Chat and the Seed bubble. See [native document reading](../docs/native-document-reading.md).

### Reviewed knowledge connections

Memories supports user-reviewed **Supports**, **Contradicts** and **Depends on** links between exact page versions. Local search suggests current neighbors one step away, with direction and rationale visible. Source corrections invalidate those suggestions. See [use, limits and recovery](../docs/native-reviewed-connections.md) and [delivery evidence](../docs/accountability/evidence/r29-reviewed-knowledge-connections-2026-09-29.json).
