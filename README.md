# ARCHi · desktop companion

ARCHi is a local-first macOS companion with text assistance, explicitly kept lessons, a shared document workspace and one continuing KIN. The native app owns assistance, memory, permissions and saved companion development. A separate Unity companion/play preview explores the same design with local presentation and practice interactions.

**Source Alpha update · package version 0.7.0.** The earlier [September 7 source Alpha](https://github.com/cr8ph8/ARCHi/releases/tag/v0.7.0-alpha.1) remains available at its original tag. This update has separate exported-source checks and is not a Beta release. See [validation and remaining work](docs/ALPHA_VALIDATION.md). No notarized installer, model weights, commerce service or release date is included.

The exported source passed retained TypeScript checks and fresh native compilation. The full native run reported **594 XCTest cases, including 31 skipped, with zero failures**; Swift Testing separately reported **234 tests in 28 suites passed**, with the installed-worker public preflight explicitly skipped. These reporting systems are not added into one pass total. A separate focused selection passed **76 checks with zero failures/skips**, including native UI fixtures. The exported native candidate passed plist and local signature verification without installation or launch. The Unity build/runtime was not rerun from this export, and native ordinary-use acceptance remains separate.

## Current source

| Surface | Included behavior and boundary |
| --- | --- |
| Native desktop | SwiftUI/AppKit workspace, floating KIN, placement controls, appearance, local Focus Staff cues, quiet and reduced motion. |
| Assistance | Local Qwen through an existing Ollama installation, optional Codex, and deliberate Compare with separate provider lanes. Stop retires the owned request. |
| Work together | Point KIN at a window, explicitly read and review a local text snapshot, then use the existing selection/explanation/revision/Apply/Undo/export flow. File import also remains available. The original app and imported original are preserved. |
| Memory and evidence | Explicit Keep/revise/withdraw controls, current source/context binding, local receipts and a native Node Lab for inspecting recorded relationships. Reading the graph makes no model call and creates no graph database. |
| Dictation | User-started on-device speech input, when supported and permitted, prepares a draft for review before Send. It is not continuous listening. |
| KIN | Core Seed and supported body presentation belong to the same individual. Appearance, learned-use records, placement and authority keep their existing owners. A local UID does not authenticate a creator or prove ownership. |
| Unity preview | Separate UI Toolkit companion/items/Relay window using bundled KIN artwork. Explicitly disconnected from saved KIN; staff, body selection and cues are session previews. No assistant client, memory store or entitlement service is added. |
| Retained game source | TypeScript Habitat, Journey, Relay and deterministic QiMon practice battles remain available as source and tests. The current native desktop build does not bundle or launch Habitat/Arena. |

The [architecture](docs/ARCHITECTURE.md) identifies the existing owners and boundaries. [Node Lab](docs/NODE_LAB.md) explains the inspection surface. The Unity preview's Seed badge is a stationary reference, not an implemented following cursor or 3D rig.

## Build the native desktop app

Native build requirements are macOS 14 or later and a Swift 6 toolchain with the macOS SDK. From the repository root:

    ./script/build_and_run.sh --verify --review --stage-only

This compiles and tests native source, constructs and locally signs a Development Review candidate, and prints its path. The stage-only flag stages a separate candidate without installing or launching it. The current native build does not require the retained TypeScript assets. Quit a selected app normally before replacing its generated bundle; the build script checks for running copies and preserves the existing bundle during promotion.

For package-only checks:

    swift build --package-path desktop
    swift test --package-path desktop

Some integration tests require explicit opt-ins or external prerequisites. A skipped test is not a pass. Building or staging an app does not verify ordinary use, full accessibility, signing for distribution or installation on another Mac.

To check the retained TypeScript source separately, use Node.js 24 or later and npm:

    npm ci
    npm run check

The public package commands operate on the included source. Private development research and accountability records are not build dependencies.

## Offline harness observation pilot

The [OO-Harness pilot](harness/README.md) adds reviewed specialist check plans, strict observation envelopes, source pins, inherited revocation and synthetic tests. Run `npm run harness:test` and `npm run harness:check` with Node.js 24+. These commands make no model calls and grant no execution authority. The normal `npm run check` includes both. This is a separate developer observation pilot; native assistant dispatch is not changed. The [research and evaluation design](docs/OO_HARNESS_RESEARCH.md) defines the remaining native integration and quality experiments.

The [source-check workflow template](docs/source-checks.yml.example) verifies the complete checksum manifest and retained TypeScript on Linux, then compiles Swift and runs selected deterministic domain tests on macOS. It uses official actions pinned to commits, read-only repository permissions, no artifact upload and no live providers or native visual tests. It is not enabled: the publishing credential lacks GitHub workflow permission. A maintainer with that permission can place this template at `.github/workflows/source-checks.yml` in a later commit, refresh the source checksums, and run it. Local validation results are recorded separately.

## Try the Unity companion/play source

The Unity project is in [unity/ARCHi](unity/ARCHi). It is pinned to Unity **6000.5.4f1**, with the Built-in Render Pipeline and Mac standalone module. Its [guide](unity/ARCHi/README.md) covers the startup scene, required baked text settings, build helper and explicit runtime smoke mode.

The preview displays **“Port preview · not connected to saved companion.”** Native assistance and memory remain in ARCHi. Previewing First Light does not grant evolution; equipping the bundled Focus Staff is temporary. The Relay practice rules are local and do not award retained progress. This source includes the separate preview, not a completed native/Unity handoff or full battle-engine port.

## Local Marketplace

Open **Marketplace** (Command–5) for Discover, My items and Create. Three bundled staff recipes support local appearance and approved pointing cues. Collect up to eight designs, make palette/crown/gesture variations, and explicitly import/export bounded JSON recipes. Add persists the collection; Equip applies for this visit; Save preferences keeps the outfit. Wearing now and Next visit distinguish these states. Imported variations open directly in Create, and an equipped pointing staff can open the existing Work together copy.

**Unregistered items do not affect the canon game.** The local Alpha registry recognizes exact bundled designs, and no item has approved Arena effects yet. Registration, ownership, limited editions and future canon approval are different things. There is no checkout, wallet, NFT issuance or production registry service. Read the [working flow and item policy](docs/LOCAL_MARKETPLACE.md) or [website guide](https://archi-it-begins-when-you-do.channelph.chatgpt.site/marketplace) (currently owner-private).

## Point at an object of interest

1. Choose **Point at a window** and move KIN's Seed over the window you want to use. A mint outline marks the current window. Hovering and choosing use window metadata; they do not read its contents or invoke a model.
2. Choose **Read this window**. ARCHi makes a local text snapshot through macOS Accessibility text or, when needed and permitted, OCR of that selected window. This is an explicit bounded read, not background monitoring. A moved, closed, changed or unavailable target must be selected again; failed or timed-out reads do not replace the current working copy.
3. Review the captured text and its source, then choose **Use in Work together**. The snapshot becomes a text copy in the existing document workspace. It does not keep following the external window.
4. Select the passage you want to discuss and use the existing explanation or revision controls. Review a proposed edit before Apply; Undo and separate draft export operate on the local working copy. The external app is not edited.

Local Qwen is the default route for the captured copy. Codex or Compare requires a separate allowance for that exact copy before Send; changing the copy invalidates that allowance. Hover, Read, Review and Use do not themselves send a question or keep a memory. OCR reads text; it does not provide image understanding, visual reasoning or camera access. Captured images are neither saved nor sent.

## Connect assistance

ARCHi does not download models. For Qwen, run an existing local Ollama service with a supported installed model (qwen3.5:9b or qwen3:8b), then use the app's connection controls. Connecting is separate from sending your draft. Automatic local-first routing, explicit provider selection and Compare retain their own connection and request state.

Send can include the deliberately shared document copy and selected passage, as disclosed by the selected route. Selecting a short passage does not by itself remove the rest of that shared copy from the request. Oversized input is rejected rather than silently truncated. Stop, source changes and request ownership prevent stale callbacks from becoming current results.

Codex is optional and requires a compatible existing signed-in Codex runtime. Kept local lessons and private temporary context are not forwarded to the external Compare lane. Neither provider automatically teaches or trains the other. Receipts distinguish offered, dispatched and cited references; a successful model call does not establish a correct or useful answer.

Optional Reactor expression is separate from core assistance and uses local artwork as its fallback. Its SDK runtime, accounts and models are not included; any live provider path retains its separate setup and controls.

## Keep control of local records

- Save wanted appearance and reply choices explicitly. Explicitly kept lessons can be inspected, revised and withdrawn.
- Evolution Save/Load and reviewed development records use the existing native owner. Saving one type of record does not implicitly save every draft or document.
- Working documents, Undo, conversation state, graph presentation and temporary context have session boundaries. Export wanted draft edits before quitting.
- Recovery controls operate on the existing native profile. The separate retained game Journey is not a complete backup of native preferences, lessons and Evolution.
- Unity preview actions do not write a native profile, saved development, private memory or ownership record.

Keep unreadable saves for recovery rather than deleting them to dismiss an error. Full combined recovery, ordinary-day usefulness, sleep/wake, multiple displays, VoiceOver traversal, resource budgets and another-Mac installation remain qualification work.

## Hampton Designed and license

**[MIT](LICENSE)** applies to the included project-authored code, documentation and runtime artwork. [Asset attribution](ASSET_ATTRIBUTION.md) and [third-party notices](THIRD_PARTY_NOTICES.md) identify their scope. External packages, SDKs, models and tools retain their own terms.

The [Hampton Designed policy](docs/HAMPTON_DESIGNED.md) describes explicit creator endorsement, distinctive appearance and balanced signature abilities. It adds no restrictions to MIT permission. Copying a badge, hash or local UID does not authenticate authorship, scarcity or ownership. Signing, editions, verified entitlements, settlement and trading remain future work. Private assistant memories and shared work are not merchandise or transferable character records.

For an issue, include the source commit, macOS or Unity version, expected behavior and a minimal synthetic reproduction. Do not include credentials, private documents, lessons or profile files. Describe each relevant check as passed, failed, skipped or not tried.

See [contributing](CONTRIBUTING.md) for ownership boundaries, local checks and the distinction between MIT contributions and creator endorsement.
