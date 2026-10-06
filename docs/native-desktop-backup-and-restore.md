# Native desktop backup and restore

## Current recovery scope — 26 September 2026

The v2 native backup now captures **five files from the currently selected profile** through **Saved & this visit → Backup & restore**. It preserves exact file presence or absence and restores the set through the existing owners.

| File relative to the selected preference path | Covered state |
| --- | --- |
| `preferences.json` | Saved settings, personal context, kept lessons and the selected companion's saved identity. |
| `preferences.evolution.json` | Saved development and retained appearance/growth choices. |
| `preferences.document-work.json` | Document task receipts, mechanical checks and explicit outcome reviews. |
| `preferences.document-procedures.json` | Retained method versions and their evidence references. |
| `preferences.reading-sources.json` | Explicitly kept reading copies, including their source text, and all retained claim/concept page versions with their anchors and review events, and reviewed-connection history. |

**This is a private-content backup.** Kept source text joins personal context and lessons in the archive; save it somewhere trusted. A file recorded absent is removed from the destination on restore. An older v1 two-file archive is accepted only when the destination has no document-work, procedure or reading-source sidecar files, including empty sidecar libraries. ARCHi refuses to combine older profile state with a newer document library.

The reading-source file was already included in the five-file backup. The earlier knowledge-page documentation incorrectly described it as excluded. The current change aligns the backup's reading-source limit with the owner's **8 MiB** ceiling and adds page-version count to the preview. The outer archive bound is calculated from all five raw-file limits after base64 expansion, plus 4,096 bytes for metadata. This does not introduce a new backup schema: outer v2 and legacy v1 remain supported, and source-library v1 and v2 are validated by `ReadingSourceLibrary`.

Pages and their source copies are restored from the same hashed byte entry. No page-only restore, source-text reconstruction or review regeneration occurs. Exact history, withdrawn versions, whitespace and file absence survive restoration or rollback. Unknown source-library schemas, malformed page histories, oversized input and changed destination bytes block the operation. A backup can retain a legitimately unavailable historical page; restoration does not make stale source anchors current.

Before replacement, ARCHi retains a rollback archive and stages a recovery journal. An interrupted restore is resolved before document owners load. Unknown or conflicting file state blocks admission and saving rather than guessing. A successful restore constructs fresh document owners and disk baselines, rebinds their observations before development reload, and clears previous answers, passage references, prepared methods and Undo. The current typed draft and working-copy bytes remain in the visit. Pending mutation receipts must be saved before backup or restore can proceed.

The scope is the **current selected profile**, not every companion profile or the profile registry. Usage and cost accounting, ARC evidence and sessions, device model settings, chats, unsaved drafts, original documents, working-copy bytes, app bundles, models and artwork assets remain excluded. Restoring a profile does not replay an action, reselect reading text for a request, or invoke a model. Other processes are checked for changed bytes but are not locked for the entire transaction; avoid a second writer using the same profile.

**Earlier delivery evidence, 25 September:** the native build succeeded and 19 focused checks across `DesktopWorkRecoveryTests`, `DesktopProfileBackupTests` and `DesktopRecoveryIntegrationTests` passed with zero model calls. These checks cover bounded disposable-profile recovery, not a personal restore or distributable Beta acceptance. That update was installed in `/Applications/ARCHi.app`; signature verification passed and native observation confirmed Liminal plus the updated recovery controls. Seven tracked profile files, 218 Unity resources and saved model settings were unchanged. No personal-profile restoration was performed. See [work recovery delivery](../output/work-recovery-2026-09-25/DELIVERY.md). The new `KnowledgePageBackupTests` separately cover page/source byte restoration, absence and legacy compatibility, interrupted recovery, and the expanded bound. Test definitions do not by themselves establish an installed-app walkthrough.

The dated procedures below are preserved as historical records. Their two-file scope and older app names must not be used as the current five-file recovery instructions.

After the first connection save, the reading library uses v5. An older app bundle cannot read it. Preserve current work before an intentional downgrade and use a compatible pre-link whole-profile backup through the existing recovery flow. See [reviewed connections](native-reviewed-connections.md).

## Earlier native recovery — 14 September 2026

14 September 2026 · Native recovery is now implemented in **Saved & this visit → Backup & restore**. It creates a verified `.archibackup`, previews the matching profile, preserves rollback, restores exact file presence/absence, and reloads existing owners. See [the native workflow and current evidence](native-everyday-upgrade.md). The new source supports Evolution v7 as well as earlier versions. No personal profile has been restored as part of development verification.

## Historical manual procedure — 13 September

The remainder preserves the earlier manual recovery procedure and its v6 checkpoint. Statements below about missing native controls describe that historical build; they are superseded by the native workflow above.

Keep both files from the same stopped app session. The preference file owns KIN's identity and kept lessons; the Evolution file owns reviewed growth and its selected body. They are written independently, so copying a live folder does not establish a consistent checkpoint.

## Choose the correct profile

| Installed app / bundle identity | Profile directory on this Mac |
| --- | --- |
| ARCHi Development Review · `com.quotient.archi.desktop.review` | `~/Library/Application Support/ARCHiDesktopReview/` |
| ARCHi Desktop Preview · `com.quotient.archi.desktop.preview` | `~/Library/Application Support/ARCHiDesktop/` |

These are the current paths selected by the native source and existing packaging script, not a claim that either directory or file was inspected during this work. On another account, use that account's Library/Application Support directory. Keep the Review and ordinary app profiles separate; their app name or a backup's date does not make their records interchangeable.

| File in the selected directory | Current contents and load behavior |
| --- | --- |
| `preferences.json` | `archi-native-preferences/v4`, up to 64 KiB. Optional saved appearance/rhythm/equipment preferences, up to 16 kept lessons, optional kept staff gesture, and the personal `qiMon` identity record. The native store reads this file when it is created. |
| `preferences.evolution.json` | `archi-companion-evolution/v6`, up to 32 KiB. Confirmed role/help/family choices, bounded useful-request and lesson-version references, optional personal KIN body choice, prior appearance records, and retained practice/Journey references. The app requires explicit **Load**. It contains no lesson text, document text or conversation. |

An absent file is a valid checkpoint condition. Record it as **absent**; do not create an empty JSON file. A present but empty, invalid or unreadable file is a different condition and must not be relabeled absent. Keep the original bytes for investigation.

## Make a checkpoint

1. Identify the app and matching profile above. Review **Saved & this visit**. If current appearance/rhythm changes should be included, use **Remember my preferences → Save preferences** in **What I remember**; normal Quit does not save these changes automatically. Finish any lesson or staff-gesture Keep you intend to retain. Before quitting, export document edits through the existing working-copy flow and copy any wanted chat or unsent text separately; the two state files do not retain it.
2. Use the app's normal **Quit**. If it offers **Save and quit** for Evolution changes, choose it to include the current growth choices. **Quit without saving** preserves only the earlier saved Evolution file. If saving reports a conflict or invalid file, the app stays open: review the existing state and preserve the conflicting file before choosing a remedy. Do not force quit to bypass this review.
3. Confirm the selected app has fully exited, including any second instance of the same profile. Do not reopen it until copying and verification finish. Closing the workspace window alone is not quitting the companion.
4. In Finder, use **Go → Go to Folder** to open the selected profile directory. Create a distinct dated backup folder elsewhere, for example `ARCHi-Development-Review-2026-09-13-2030`. Never reuse an earlier checkpoint folder. Copy each of the two files that exists; keep its exact filename. Do not move the originals or combine files from different checkpoints.
5. Add a small checkpoint note: source app and bundle identifier, full source directory, date/time and timezone, app build identifier if known, and each filename's present/absent status. For every present file, record byte length and SHA-256 for both the source and copy. Use a read-only checksum tool such as macOS `shasum -a 256`; matching names, Finder previews and equal file sizes alone are insufficient. Require both hashes to match. Record invalid/unreadable files separately and do not mark them verified.
6. Check that every copied file is a regular file, not an alias or symbolic link. Keep the backup folder private because it can contain personal lesson text. Preserve the verified checkpoint unchanged; use a separate copy for the rehearsal below.

No checkpoint is complete until each expected file has either a verified copy or an explicit absent entry. This procedure does not make the two application writes transactional; stopping the writer is what makes the checkpoint coherent.

## Rehearse recovery in a disposable profile first

The installed app has no arbitrary-profile chooser or two-file restore command. The current rehearsal seam is developer-assisted and uses the existing native store, not a replacement state system:

1. Create a fresh temporary directory and copy the verified checkpoint pair into it under the same filenames. Preserve absence exactly. Recheck these copies against the checkpoint hashes.
2. Read the temporary `preferences.json` through `NativePreferencePersistence.read`. If it is present, require valid decoding; if absent, expect the owner's empty/default document. Construct `CompanionStore(preferenceURL:)` against this temporary path with `allowsPlay: false` and an injected client that fails any model invocation. Do not create the ordinary app, a game host, a provider connection or a new identity.
3. Check the loaded personal identity, lessons and optional saved preferences against the decoded checkpoint. Construction alone must not rewrite either file. If the Evolution file is present, call the existing `evolution.load()` explicitly and require success; if absent, expect no restored growth rather than an implicit reconstruction.
4. Check that a kept First Light record affects the body only when its origin matches the saved KIN. The cursor remains Core Seed for an active personal KIN. A returned body remains Core Seed. Missing or mismatched identity must not receive another individual's body. Expired or withdrawn lessons must not be recreated from their historical digest references.
5. In the disposable copy only, exercise Return/Resume where an appropriate record exists, then explicit Save and another new-store/Load cycle. Check identity and kept lesson ownership remain intact. Any Save to a file that already exists must follow a successful Load of that exact baseline. A stale writer should report conflict rather than overwrite a different saved file.
6. Record the validation result and limitations next to the checkpoint; shut down the temporary store. Keep the verified backup untouched. A failed rehearsal means investigate the preserved files or choose another checkpoint before restoring the real profile.

This document does not supply an executable recovery script. The three `DesktopProfileRecoveryTests` exercise this two-file copy rehearsal through the injection seam without reading a user's profile.

## Restore the selected desktop profile

1. Complete a successful disposable rehearsal. Confirm the checkpoint belongs to the intended app/profile and individual. Quit the destination app normally and confirm it has exited.
2. Make a separate **before-restore** checkpoint of the current destination pair using the same copy, absent-file and checksum procedure. This is the rollback copy; keep it even if the chosen backup is older or appears healthier.
3. With the app still stopped, move any current destination files into a distinct holding folder within that rollback checkpoint. Copy the selected checkpoint's present files into the destination directory under the exact original names. For a file recorded absent, leave that destination filename absent. Do not leave a newer leftover file paired with an older restored one, and do not edit JSON identifiers to make a mismatch appear valid.
4. Verify destination file lengths and SHA-256 against the selected checkpoint, including recorded absence. Retain regular-file status and private access. If any copy or check fails, keep the app stopped and restore the before-restore pair instead.
5. Open only the intended app. Inspect **What I remember** and **My QiMon** against the checkpoint. In **Life with KIN / Evolution**, explicitly **Load** the restored Evolution file if one was present. Verify the body choice, Seed cursor, retained references and confirmed guidance. A successful launch alone is not recovery proof. Do not press **Save** over a file the new session has not successfully loaded.
6. If validation fails, quit without replacing the selected save, preserve the failure details, and restore the before-restore pair with the app stopped. Recheck hashes before reopening. Keep both checkpoints until normal use has confirmed the recovered state.

Restoring application data does not restore an older executable. Retained `.app.previous…` bundles are separate build rollback artifacts; they are not profile backups. Prefer the same supported build or a verified compatible build for the rehearsal, since older executables may reject newer schemas.

## What this checkpoint excludes

| Material | Why it needs separate handling |
| --- | --- |
| Shared source documents, edited working copies and undo history | Keep original files and verified exports separately. The desktop state pair does not contain document text or an editing journal. |
| Unsent prompt, voice-review text, captured audio and recent local dialogue | These are session handling. The current pair is not a transcript archive and does not capture an in-progress voice exchange. |
| Suspended Habitat/Arena saves and full Journey/battle history | The retained host uses its own website data store. The native pair holds identity associations and bounded references, not that full history. This procedure does not open, copy or qualify the suspended game store. |
| Artwork sources, app bundles, Ollama models and authored Blender/Unity work | These are separate assets and software. Preserve them through their existing project/build backup practices. |
| Live placement, selection, temporary light state and request activity | These are session/spatial state. Recovery must establish current desktop context rather than replay stale screen coordinates or unfinished work. |

This is a desktop two-file recovery procedure. It is not an all-platform account backup, device synchronization system, or complete project archive.

## Existing evidence and remaining qualification

Current source tests provide useful component evidence: `KeptLessonsTests` cover envelope validation, known migration, save/reload, conflicting writes and preservation; `EvolutionSaveConflictTests` cover stale Save/Forget, external creation/removal, malformed repair and known legacy baselines; `KinGrowthIntegrationTests` and `KinCursorPresentationTests` cover disposable store recreation, explicit Save/Load, body/cursor continuity and lesson withdrawal; `QuitRetentionTests` cover normal quit decisions and failed-save retention. These tests do not by themselves prove that someone copied the correct two real files or restored a particular user's profile successfully.

The new `DesktopProfileRecoveryTests` defines three disposable test cases through the existing owners: an exact two-file copy and independent byte/SHA-256 readback followed by preference restoration and explicit First Light Load; a checkpoint with Evolution recorded absent; a foreign-origin growth record that leaves KIN in Core Seed; and a damaged-copy rejection followed by recovery from the unchanged verified checkpoint into a fresh directory. The complete fixture includes saved preferences, a lesson, KIN identity and a staff gesture. It also checks that unsent prompt, document text, live position and visit activity are not fabricated during recovery. These helpers live only in the test target and are not an app backup service.

Validation status: **all three recovery tests passed** in the 13 September desktop-retention run (101 XCTest and eight Swift Testing cases passed overall, with no skips or failures). The fixture does not cover every presence combination, physical storage failure, interrupted Finder operations, a live user's profile, or native post-restore inspection. Live user-profile backup and restoration remain separate until actually performed. See the [test log](../output/desktop-retention-2026-09-13/focused-tests.log) and [delivery checkpoint](native-desktop-retention.md).

No owner-profile contents were read, copied or restored for this procedure. Test fixtures use unique temporary folders and make zero model calls.

Source owners: [profile selection](../desktop/Sources/ARCHiDesktop/ARCHiDesktopApp.swift), [ordinary path and store injection](../desktop/Sources/ARCHiDesktop/CompanionStore.swift), [native preference envelope](../desktop/Sources/ARCHiDesktop/KeptLessons.swift), [Evolution persistence](../desktop/Sources/ARCHiDesktop/CompanionEvolution.swift), [normal quit review](../desktop/Sources/ARCHiDesktop/CompanionQuitReview.swift), [personal presentations](../desktop/Sources/ARCHiDesktop/PersonalQiMonPresentation.swift), [retained game host](../desktop/Sources/ARCHiDesktop/HostedPlayHost.swift), [bundle naming](../script/build_and_run.sh).
