# First Signal installation safeguard

28 October 2026 · focused patch against PR #10 at `2e2ab0f0c7fe0b5d5f376a3061f8969d445d8cfc`.

**Prepare a new staged candidate. Do not replace the working application until the authoring-Mac evidence below is complete.** This patch preserves chapter bytes and blocks unsafe promotion. No installed application, real chapter, bookmark or save was changed during its remote development.

## Keep the owners distinct

| Surface | Resource and state owner | Effect of this patch |
| --- | --- | --- |
| Native ARCHi | Native profile/preferences, kept lessons, methods and their existing journals | Packaging retains `com.quotient.archi.desktop.review`. No profile migration or write. Contextual memory remains an explicitly assessed suggestion. |
| Retained QiMon practice | TypeScript rules-v1 Journey/roster/battle owners | No practice build is substituted for First Signal. A native build does not deploy this TypeScript surface into the chapter. |
| First Signal inside ARCHi | Separately authored `QiMonFirstSignalWeb`; persistent WebKit store; chapter localStorage | Copy the whole preserved chapter into the candidate and recheck it. No gameplay or save-format edits. |
| Earlier adventure | `QiMonLocalGame`, standalone bundle `com.quotient.thedrifter.qimon.mac`, independent campaign | Preserve the shortcut metadata. A bundled earlier app blocks this web-only recipe until its own packaging/preservation is reconciled. |

The authored First Signal source/build is absent from this curated repository. Its gameplay, dependencies, save schema and current progress cannot be reconstructed from retained practice or the host's display projection.

## Findings in the inspected source

`QiMonEmbeddedGame.refreshLocation()` first considers `selectedEmbeddedFolder.v1` in `com.quotient.archi.qimon-local-play`. A present but invalid bookmark stops discovery. With no bookmark it tries, in order:

1. `<host>.app/Contents/Resources/QiMonFirstSignalWeb`.
2. `QiMonFirstSignalWeb` adjacent to that host app.

It does not search an authoring directory or a retained TypeScript `dist`. A candidate staged elsewhere cannot discover a chapter adjacent only to the installed app unless it is copied into the candidate. Copying a new chapter does not override an explicit bookmark.

`QiMonEmbeddedAssets` requires `qimon-build.json` (schema 1, game `qimon-first-signal`, entry `index.html`, at most 4,096 bytes) and a nonempty entry below 131,072 bytes. It does not authenticate the remaining dependency set. A missing JavaScript bundle, image, audio file or WASM can therefore survive discovery and break play later. The local server serves bounded static files under its selected root, rejects traversal and hidden paths, disables workers, and limits each response file to 64 MiB. Network navigation and native save admission are separate restrictions; neither establishes chapter completeness.

The embedded save boundary is:

| Field | Required existing value |
| --- | --- |
| Native bundle ID | `com.quotient.archi.desktop.review` |
| Web origin | `http://127.0.0.1:8767/` |
| Persistent WebKit store UUID | `A4A19A25-351B-45B6-9D70-3B15D0A02817` |
| Chapter localStorage key | `qimon.first-signal.chapter.v1` |
| Selection defaults suite | `com.quotient.archi.qimon-local-play` |
| Embedded folder selection key | `selectedEmbeddedFolder.v1` |

Changing the origin (including port or `localhost` versus `127.0.0.1`), persistent store, key, app identity or selected build can make a saved journey appear absent while leaving its old bytes on disk. An incompatible chapter can also stop recognizing the save without any path change. The host's **Export journey** creates a copy of the inspected chapter value; it is not a backup of all WebKit state and does not establish a restore/import capability. Native profile backups do not cover this game's store, retained browser practice or the standalone campaign.

Before this patch, `build_and_run.sh` created a fresh native bundle, copied qualified Unity/resources, signed a destination-filesystem copy, and moved the previous app into recovery before promotion. Neither this script nor `desktop/Package.swift` packaged First Signal. Thus a chapter existing only inside the old app would move into rollback storage while the new app would lose its discovery path. Keeping the old bundle is useful recovery but does not keep the game available in the updated app. The script leaves application-support data alone; that alone cannot guarantee that the new app reconnects to the same store.

`--build-only` still installs; it only suppresses launch. Use `--stage-only --stage-dir NEW_ABSOLUTE_DIRECTORY` for preparation. This patch does not change those flag meanings.

## Implemented preflight

The installer now runs the same guard on staging, normal installation and `--build-only`; there is no skip flag.

1. `inspect_first_signal_selection.swift` reads the two existing folder/app bookmark keys without refreshing or writing them. It emits resolved paths, stale flags and bookmark digests, never raw bookmark bytes or saves. Resolution uses no UI or mounting. Inspection errors and stale bookmarks stop the recipe.
2. `first_signal_preflight.py capture` validates the existing native bundle ID/executable, records its executable/plist hashes, inventories bundled/adjacent/explicitly selected chapter candidates, and checks the current host's save-owner pins. Missing, malformed, divergent, linked, special or hidden chapter inputs stop preparation. `.DS_Store` is the sole ignored file. Any explicit chapter bookmark inside the old app is refused, including the standard resource path: a bookmark can follow the old folder's file identity into recovery instead of retargeting to the new copy at the same pathname. Preserve the chapter outside the app, deliberately choose that stable build in the current UI, and verify the same journey before retrying. The preflight never edits that selection for the player.
3. Existing chapters are preserved as a complete file/directory inventory with per-file sizes and SHA-256 digests. Every discovered/selected chapter must agree. If no working installed source is available, a supplied `--first-signal-build` must match an independently reviewed `--first-signal-manifest`. A supplied build that differs from an existing chapter is blocked; chapter upgrades/save migrations need their own review.
4. `package` copies into a new `Contents/Resources/QiMonFirstSignalWeb`, verifies exact inventory equality, rechecks the sources, and writes `FirstSignalPreservation.json` before native build sealing and signing. This receipt contains the owner pins/inventory and `PRESERVED_BYTES_ONLY`, with no authoring paths or bookmark data.
5. After signing and copying to the destination filesystem, `verify` re-inspects selection and rechecks the actual final candidate, old executable/plist, source chapters, discovery candidates, host source and receipt. Any change refuses promotion before moving the working app or reserving rollback storage. Existing process, signature, artwork, Unity and rollback guards remain active.

Build/copy/signature failure stops before promotion. A partial newly reserved staging directory may remain empty after failure; inspect it and choose another new path. The working application and game sources are never used as copy destinations. No save directory is inventoried, copied, merged, renamed or deleted by the preflight.

The guard is a cooperative local preservation check, not a sandbox against a hostile same-user filesystem writer. There is no atomic lock spanning defaults, chapter files and the final app rename; keep other installers and chapter writers stopped. A matching inventory cannot detect an already-incomplete baseline or an incompatible save reader. The source-pin checks constrain this recipe; they do not prove the constants used by a previously compiled installed binary. Establish those through the installed build/source evidence and runtime baseline below. No CI result grants installation approval.

## Safe preparation on the authoring Mac

First reconcile the focused changes into the existing authored workspace, identified in PR #10 as `~/Documents/ChatGPT/ARCHi` on the authoring account. Do not copy this curated tree over that workspace. Preserve unrelated native, Unity, mobile, First Signal and unpublished work.

After identifying the exact working chapter in the current app, create an independent resource baseline outside the chapter/candidate. The command refuses to replace an existing evidence file:

```sh
python3 script/first_signal_preflight.py manifest \
  /absolute/path/to/known-working/QiMonFirstSignalWeb \
  /private/tmp/first-signal-resources-NEW.json
```

This hashes files; it does not establish that the chosen build plays or reads the real save. Generating a manifest from the unverified candidate is not independent validation. Retain the baseline privately with the known working build's provenance.

When the installed, adjacent or explicitly bookmarked working build is present, the script preserves it automatically. Prepare only a new candidate:

```sh
bash script/build_and_run.sh --stage-only \
  --stage-dir /private/tmp/archi-first-signal-review-NEW \
  --unity-player /absolute/path/to/qualified-player.app
```

If a source must be supplied explicitly, add both:

```sh
  --first-signal-build /absolute/path/to/known-working/QiMonFirstSignalWeb \
  --first-signal-manifest /private/tmp/first-signal-resources-NEW.json
```

Retain any already-required `--liminal-finish` and `--liminal-light` qualification arguments for the same player/body. These are placeholders for reviewed local resources, not downloads. The stage command neither installs nor launches. Inspect its plist, signed resource inventory, `FirstSignalPreservation.json`, `ARCHiBuildIdentity.json` and signature before considering any launch. The candidate retains the real app identity/store pins, so launching it in the authoring account can touch the same saves. Do not launch a staged copy casually or alongside the working app. Use a separate disposable macOS account for initial runtime qualification with synthetic saves.

## Exact evidence still needed from the authoring Mac

None of the following was inspected in this remote Linux session:

| Evidence | Required record and acceptance condition |
| --- | --- |
| Current authored source | Actual workspace path, branch/HEAD, dirty/untracked inventory, applicable owner instructions and reviewed reconciliation diff. Record actual First Signal source and build locations/version; confirm they are not replaced by retained practice. |
| Working installed baseline | Exact app path, plist identity/version, executable hash, deep/strict signature result, existing build receipt if present, and source identity corresponding to the installed host. Establish the previous origin/store/key bindings rather than inferring them solely from the new source. |
| Current discovery/selection | Read-only inspector output; resolved embedded path and whether bookmark/bundled/adjacent wins. Resolve stale/missing/ambiguous locations deliberately in the existing UI before retrying. Record any standalone earlier-adventure path/owner separately. No raw bookmark or private save needs to be posted. |
| Complete real chapter | Working `qimon-build.json` and entry; exact full dependency inventory/digests and matching independent baseline. Verify referenced assets, audio/WASM and offline startup through the real host. Preserve the working source/build outside the app as well. |
| Existing First Signal save | In the working app, record a local baseline: operator/companion, progress, revision and journal summary; create an explicit journey export if available. Identify the actual OS-managed WebKit store/location and retain a verified private backup with its owner stopped. Record backup paths/digests locally. Do not assume an export alone can restore everything. |
| Other existing owners | Compatible native whole-profile recovery evidence before any v11 write, selected-profile identity and backup; retained QiMon Journey/roster separately if used; standalone campaign separately if present. No automatic migration or combined archive is supplied by this patch. |
| Qualified presentation inputs | Actual Unity player path/protocol/capabilities/signature, selected Liminal resource manifests/digests, and the qualified Proto artwork missing from the curated snapshot. Keep asset-dependent failures separate from contextual-memory behavior. |
| Final staged candidate | New stage path, exact final signed-bundle inventory/hash evidence, candidate/source/content IDs, unchanged First Signal resource inventory, matching save-owner pins and deep/strict signature. The unsigned payload receipt alone is not a final signed-artifact hash. |
| Runtime acceptance before installation | In a disposable account: chapter starts, dependencies load, synthetic save/reopen works at the fixed origin/store, stopped-port/conflict behavior is safe, and native/retained suggestions still require explicit action. Check the actual selected orb presentation, Unity acknowledgment and input separately. |
| Deliberate later delivery | Separate installation authorization, verified backups/recovery, quit all owners, and inspect the selected source again. After any eventual authorized installation, verify the real existing journey resumes with the same owner/progress and save/reopen still works. Only that later evidence can close installed-app integration. |

If any resource, selected path, save owner, source identity or recovery prerequisite is unknown, retain the current app and stay at staging. Do not relabel/move saves, reset defaults, delete WebKit state, or point a newer v11 native profile at an older binary to make a test pass.

## Checks and limits

Local Linux validation: **74 synthetic tests passed** across `test_first_signal_preflight.py` (22), `test_build_and_run_staging.py` (19), `test_native_build_identity.py` (8), and `test_source_release_preflight.py` (25). Tests cover missing/existing/adjacent/bookmarked chapters, dependency mismatch despite a valid marker, invalid/stale selections, conflicting candidates, changed source/installed binary/owner pins, corrupt copies, failed native builds/staging, an app opened during final preflight, existing destinations/collisions, and unchanged separate synthetic save owners. The orchestration suite runs a disposable script copy with fake compiler/signature/process/defaults tools; copies and moves remain real and confined to fixtures. It does not run macOS signing, WebKit or an installer against a real app.

The source export allowlist now includes both preflight helpers and their tests. Its bounded build-recipe dependency check recognizes Swift helpers as well as Python. `native_build_identity.py` includes packaging Swift scripts in the input inventory. Refresh and verify complete `SOURCE_SHA256SUMS` coverage after final reconciliation; a checksum list never certifies omitted local game resources or gameplay. `check_source_parity.py` compares its existing scoped authored/publication cohort with exact approved resource-pin transformations; it is not a general First Signal resource audit. Source release preflight and archive checks concern curated source/publication, not installed-app acceptance.

The base manifest's 1,861 source hashes and complete coverage were verified locally. The focused patch refreshes complete coverage to 1,866 files. Its new helper dependency closure and new-file scanner checks passed; source collection reported zero blockers. Bash syntax, Python compilation and diff whitespace checks passed. These are source checks, not publication or installation qualification.

New `.github/workflows/first-signal-packaging.yml` exercises the synthetic packaging checks, typechecks the read-only inspector on macOS and runs existing synthetic `QiMonLocalGameTests`. Adding this workflow is not evidence that its macOS job ran. This Linux session cannot compile or execute the macOS inspector/host, sign a native candidate, or inspect the real game/save. No actual native candidate was built or installed here.

The earlier failed memory notification is superseded at the inspected commit: [contextual-memory run 40738425097](https://github.com/cr8ph8/ARCHi/actions/runs/40738425097) passed both jobs. [PR #10](https://github.com/cr8ph8/ARCHi/pull/10) records 74 XCTest plus 12 Swift Testing tests, 80 TypeScript tests, and 17 synthetic browser checks. [Orb run 40738425576](https://github.com/cr8ph8/ARCHi/actions/runs/40738425576) passed protocol and OrbPresentationTests, then failed the Unity presentation assertions documented as requiring missing qualified Proto art. None of those results establishes First Signal resource delivery or installed save continuity; the missing artwork is not evidence of a new memory defect.

Source references: [original installer](https://github.com/cr8ph8/ARCHi/blob/2e2ab0f0c7fe0b5d5f376a3061f8969d445d8cfc/script/build_and_run.sh), [embedded host](../desktop/Sources/ARCHiDesktop/QiMonEmbeddedGame.swift), [standalone shortcut](../desktop/Sources/ARCHiDesktop/QiMonLocalGame.swift), [memory contract](contextual-memory-influence.md), [source ownership](source-ownership.md), [native recovery scope](native-desktop-backup-and-restore.md).
