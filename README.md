# ARCHi source candidate

**Native Qwen update — 19 September:** ARCHi automatically starts or reuses local Ollama and verifies the installed Qwen model. The default Qwen-first route can use one Codex fallback after an eligible failure; a retained local-only option stays available. Local memory stays out of fallback, and window snapshots require exact-copy external permission. [Operation and limits](docs/native-qwen.md).

> **Code-only draft update — 18 September 2026.** New Liminal, Ball of Light, Proto and KIN rig artwork is withheld pending its separate redistribution decision. Existing published artwork remains included (PNG metadata may be removed). This branch is available for code review, but cannot reproduce the full current desktop/Unity presentation; Unity asset validation and artwork-dependent tests are expected to fail until those resources are admitted. The complete local candidate was tested separately. See [validation and omitted resources](docs/ALPHA_VALIDATION.md). No Beta or downloadable application release is declared.

ARCHi combines a native macOS companion workspace, a Unity companion and practice area, and a local item marketplace. This packet prepares a source update. It is a development source snapshot, not a Beta declaration or a notarized installer.

The native Swift app owns assistance, private working context, the companion's identity and saved development. Unity presents the accepted native companion state and a separately entered local Arena practice session. KIN, Ball of Light and personal Liminal Seed appearances retain the selected individual's identity. Shared color choices travel through the native-to-Unity appearance contract. A Python/SQLite creator service owns local accounts, published recipe listings and acquired inventory; the app separately owns installed designs and equipment. This source provides no payment, wallet, ownership-transfer, signed-edition or Internet marketplace service. A source license or copied design does not authenticate a creator endorsement.

## Document outcome review

The native working-copy path now retains explicit Helpful, Needs correction and withdrawn judgments after Apply. Usage reconciles the exact event; Add to learning review and Save evolution remain separate choices. A correction opens a user-authored Memory draft and requires Keep. Lesson-use confirmation requires the exact cited version to remain kept. Interrupted Undo permits retry or withdrawal, and unreadable feedback history blocks loading older learning. See [active document work](docs/active-document-work.md).

This bounded feedback bridge passed 21 focused journal/store checks using injected clients and temporary profiles. It does not automatically adjust Q2E state, generalize lessons or certify skills. New native interaction and live-provider acceptance remain separate from these checks. Reviewed metadata stays pinned at the 64-record capacity; explicit history removal remains future work.

## Current desktop and Arena increment

The desktop Arena entry accepts supported personal Seed colors instead of leaving Liminal/Garnet behind a disabled button. The bundled player validates and acknowledges appearance/color and the exact source art; changing presentation does not grant saved development.

Arena offers solo practice and two people on one Mac. Player 1 uses `1 / 2 / 3`; Player 2 uses `J / K / L`. `M` switches solo/two-player mode, `N` starts a new bout, `B` returns to the companion, and Escape stops motion. Both players lock a choice before a round resolves. Application shortcuts such as Command+N do not reset a match. Guest ECHO and paired history are session-only. Network transport, private-device pairing and reconnection are not implemented.

The native workspace includes personal Seed/color selection, Token Steward accounting, ARC evidence in Node Lab and a pinned local checker replay. These remain distinct from learned capability certification, actual paid-provider budget enforcement and online multiplayer. Original/private profiles are never part of the source export.

The ARC replay checks pin the macOS arm64 Node 24.18.0 executable and its dependency bytes. Other hosts fail that qualification check until separately qualified; the replay does not silently repin a different runtime.

## Build from source

Use macOS 14 or later and a Swift 6 toolchain for the native target, plus Python 3.11 or later for the creator service and source preparation checks. The Swift package declares no external package dependencies. Local preparation used Node 24.18.0, npm 11.16.0, Python 3.11.9 and Apple Swift 6.4 on arm64; other environments remain to be qualified. Run these commands from a fresh source checkout:

```sh
npm ci
npm run check
swift build --package-path desktop
swift test --package-path desktop
python3 -m unittest discover -s scripts/tests -p 'test_*source*.py' -v
python3 -m unittest discover -s marketplace/tests -v
```

`npm run check` in this proposed public package runs the retained TypeScript, synthetic ARC, foundation, PWA and asset build checks. It does not depend on private research/accountability records. `swift build` and `swift test` compile and test source; they do not install or launch the application. Tests that require an explicit native UI or installed-worker opt-in must be reported separately with their skipped counts.

The [creator marketplace service](marketplace/README.md) uses Python 3.11+ and SQLite with no new runtime dependencies. Start an empty persistent development service explicitly with `python3 -m marketplace --database marketplace/data/development.sqlite3`, then connect through the native Marketplace. It provides local accounts/sessions, versioned draft/publish/archive, catalog search, validated recipe downloads and acquired inventory. Publishing is local catalog visibility; inventory and the app's installed/equipped collection remain separate. Database files, sessions and user recipes are excluded from source exports. [The API contract](marketplace/API.md) and [current Arena/creator integration record](docs/unity-arena-and-creator-marketplace-2026-09-16.md) describe the scope. This does not include payments, currency or Internet hosting.

Unity source is pinned to 6000.5.4f1 with its macOS standalone module. Once that Editor is installed, no other Editor has this project open, and source writers are finished:

```sh
bash script/build_unity_port.sh
```

That command builds a development player and writes its receipt under `output`. Inspect the build receipt and then qualify the native-to-Unity interaction. A successful Editor build does not prove the native handoff, rendering, keyboard, VoiceOver, reduced motion or recovery paths work. The runtime FBX files and their `.meta` files must be present; earlier export tooling omitted FBX.

For a locally signed review bundle, use the existing `script/build_and_run.sh` only after exporting any unsaved draft and keeping the selected review app closed. Its default action launches an app; `--review --stage-only` stages a separate candidate without launch. This is development signing, not distribution signing. An optional existing Unity player can be supplied with `--unity-player` after its bundle contract is verified.

## Source scope and release gates

The source preflight is read-only by default:

```sh
python3 script/source_release_preflight.py --root .
```

It exits 1 while release blockers remain, including absent notices, dirty or unidentified source, out-of-scope tracked paths, unresolved asset redistribution, stale checksums, metadata findings and missing validation tied to the current source digest. Exit 2 means the preflight could not complete. A passing preflight is evidence review, not permission to publish or a notarized-app claim.

`script/archive_source_candidate.py` can package a source candidate only when its allowlist, bounded scan and checksum manifest agree. It creates new archive/receipt files outside that candidate, normalizes tar/gzip metadata, reads every member back and verifies the source remained unchanged. The retained `script/prepare_source_candidate.py` is the development workspace's exporter; its curated `release/proposed/` inputs are workspace preparation records, not part of this distribution. Its fixture tests are included for the metadata transformations and preservation guards.

See [validation scope](docs/ALPHA_VALIDATION.md), [asset attribution](ASSET_ATTRIBUTION.md) and [dependency notices](THIRD_PARTY_NOTICES.md). MIT text is carried forward from the existing ARCHi source release. Newly added rigs and artwork require their own recorded provenance and redistribution review; this draft does not silently grant rights to them.

Private conversations, profiles, saved preferences/evolution, research attachments, editable Blender originals, generated evidence, installed tools, model weights, dependency caches and application binaries are excluded. Source builds may require separately installed tools or packages governed by their own terms.
