# Unity Arena, creator marketplace and interface consolidation

16 September 2026. Active local implementation and verification record.

## Requested outcome

Restore Unity Arena and its function to the system, consolidate redundant controls and clean up the interface. The owner explicitly restored Arena to scope, superseding the earlier pause for the Unity implementation. The subsequent Marketplace clarification was **“Complete creator marketplace first”**: accounts, listings, publication, downloads and inventory. Payments are outside this increment.

The working source is this repository, as described in the workspace map. Earlier frozen source candidates and receipts remain immutable. Current independently authored character assets are preserved. A new candidate will be prepared from the settled source, rather than silently refreshing an earlier verified package.

## Working checklist

- [x] Read current source, shared context, relevant skills and preceding release evidence; preserve pre-edit main-owned files in `output/unity-arena-restoration-2026-09-16/before-main/`.
- [x] Consolidate Appearance/Growth under Companion and Connections/Conversation/Comfort/Advanced under Settings, using existing routes and state.
- [x] Replace duplicate Evolution launch and Wardrobe equip controls with navigation to the owning Unity and Marketplace workspaces; preserve the gesture editor.
- [x] Wire explicit Companion and Arena actions into Unity Area and add Enter Unity Arena to the native menus.
- [x] Restore the existing Unity Arena for a native session, preserve the native individual and outfit, and support identity-free local practice without manufacturing a KIN record.
- [x] Verify session acknowledgment, one-player ownership, return/reopen, Quiet/Reduce Motion, stale/disconnected/Stop behavior and local practice results in a captured source copy.
- [x] Implement and validate persistent creator accounts, drafts, immutable listing versions, publication/archive, catalog and inventory in a local development service.
- [x] Connect the native Marketplace to that service with explicit account actions, publication and acquisition; retain validation and explicit admission into the existing on-Mac item collection.
- [x] Complete native UI density/navigation polish and exercise both minimum and wide layouts.
- [x] Run final native/service/Unity checks against settled source, with skips and warnings recorded.
- [ ] Prepare and verify a fresh source package and separate native review bundle.

## Owners and boundaries

`CompanionStore` and `EvolutionStore` retain the native individual's identity, accepted development, preferences and installed item collection. Unity has one explicitly opened session owner with Companion and Arena destinations. The existing Arena runtime owns disposable practice rounds; it cannot commit native development or replace the saved individual. The retained WebKit game stays out of primary navigation so it is not a second active Arena.

The creator service owns accounts, listing history and account inventory. Downloading a published recipe does not execute package-supplied code. The native collection remains the explicit owner of installed items and equipment. A publisher's identity and rights declaration are records, not independent verification of legal rights or creator endorsement.

Local development service tests use disposable accounts/databases. No personal recipe is published, no installed app or personal profile is replaced, and no external service is deployed by this increment. A working development service is distinct from public hosting and production operations.

## Initial evidence

`WorkspaceNavigationTests` and `DesktopDevelopmentScopeTests`: five tests passed. All current destinations have exactly one reachable sidebar parent, grouped navigation retains draft/preferences and does not write the saved profile or open Unity. UI interaction and combined final results are recorded after execution.

The combined navigation/Unity model slice passed 11 tests with one explicit native-layout prerequisite skip and no failures. The service was independently exercised through `python3 -m unittest discover -s marketplace/tests -v`: 40 tests passed, including an actual process restart, creator-to-collector HTTP flow, ownership checks, hashed account/session secrets, exact recipe fingerprints and recovery after an interrupted response. The backend receipt at `output/unity-arena-restoration-2026-09-16/marketplace-service/verification.json` binds the checked files and log; local execution evidence is retained outside the source packet.

The later combined native run passed 44 tests with no skips or failures, including actual account creation, sign-in, draft, publish confirmation, acquisition, download review, installation and explicit equip. Both Home sizes, grouped navigation and Unity Area layouts were exercised with synthetic profiles. A separate 11-test slice verifies Seed preference reopen/backward compatibility, voice retirement and navigation without redundant state publication. Earlier failed attempts remain in the local logs: they exposed a missing Seed preference whitelist entry, two accessibility/harness issues and redundant idle/navigation publications, which were corrected. The direct accessibility test still reports a SwiftUI publication warning when returning from Growth to Home, once at each size, including after a settled-render check. The route and preservation assertions pass; the warning remains recorded for native accessibility/ordinary-use qualification and is not represented as resolved.

The captured Unity build passed 74 native-presentation checks and 136 Relay checks with zero build errors or warnings. Runtime groups passed 44 native/Arena, 24 first-run local-roster, 41 retained Arena and 43 retained-port checks. Nineteen native connection tests, including three real-player visits, then passed with no skips or failures. These overlapping groups are not a unique product test total. Later independent art edits were detected without changing the tested copy; the new source export receives its own build and runtime qualification.

Current root accountability and structure checks pass. ARC typechecking and 27 tests pass. Independently authored Token Steward, ARC and Seed work arriving during this increment is preserved and included in the combined source validation; these checks do not substitute for that work's own acceptance record.

The combined retention/accounting slice passed 80 tests with one explicit live-Qwen prerequisite skip and no failures. Opening or refreshing a missing usage journal creates no profile directory or lock file; actual mutations retain the existing atomic writer lock. A surviving Compare provider can record its terminal usage without reviving a withdrawn local lane or rewriting companion state. The new Particle Seed starter shares the existing KIN Seed portrait intentionally; that alias retains one individual. Source preparation includes the synthetic fractional-rate ARC fixtures required by both language implementations. Unity's portable foundation check validates bundled runtime assets; authored-file parity is reported separately and has its own strict authoring entry point.

## Try the creator service

Follow the [service guide](../marketplace/README.md) to start an explicit private SQLite database, then open Marketplace and connect to its loopback address. Create an account and sign in. Create saves a draft; Publish makes that version discoverable in this running service. Account library retains acquired recipe versions across service restarts. Download opens native recipe review; Add installs it on this Mac, and Equip is a separate action.

Accounts and listings are persistent service state. The native sign-in token stays only in memory, so quitting the app requires signing in again. An interrupted mutation retains its request and retry key while the app session remains open. Public hosting, payment transactions and password-recovery operations are outside this development service.

## Current Unity Seed support

The qualified player supports KIN's Particle Seed, ARCHi's Ball of Light, kept First Light and Proto expression. `ARCHiSeedAppearanceVersion=1` advertises support for both primary Seed looks; native acknowledgment checks the requested style while retaining the same individual. Older players that lack this capability remain available for Particle Seed, while Ball of Light requires choosing an updated player. Changing to an unsupported Seed style retires that older projection. Identity-free local roster practice remains available without a saved KIN.

Final frozen-source qualification passed 774 XCTest cases with 47 explicit prerequisite skips and no failures; the Swift Testing suite passed 234 cases across 28 suites with one installed-worker opt-in skip. Separate native acceptance passed 44 Marketplace/Home/Unity Area cases and 20 Unity connection cases with no skips or failures, including both primary Seed looks in the real player. The creator service passed 40 tests, source preparation passed 27, and the source-only web checks passed. Unity passed its build, 77 native and 136 Relay scene checks, 7,771 parity assertions, 104 portable evolution checks, and four runtime groups (44 native Arena, 24 first-run roster, 43 retained Arena, 43 retained port). These overlapping groups are not a unique total. The two direct accessibility Growth-to-Home publication warnings remain recorded; the portable source packet explicitly reports authored-file parity unavailable. Generated logs, captures and archive/readback receipts remain outside the source packet in `output/unity-arena-restoration-2026-09-16/`.

## Remaining publication work

The previous source-preparation gates remain applicable to newly frozen bytes: precise source/asset review, a clean release commit and explicit publication scope. New creator-service deployment/authentication operations, public account availability, distribution signing, another-Mac installation and ordinary-use/accessibility qualification require their own evidence. No prior release claim is promoted by a successful local build.
