# Local marketplace and canon item policy

14 September 2026 · Implemented desktop development Alpha

The native Marketplace (sidebar, Window menu / Command–5, menu-bar item and Wardrobe link) shares the existing companion, renderer, Work together and native profile. It adds no second character, model router or game save. The creator catalog is a separate persistent loopback development service, described in the latest section below and `marketplace/API.md`.

## Working local flow

- Discover three bundled recipes: Focus Staff, decorative Starlight Staff and Grove Staff.
- Inspect static artwork and the exact supported local action. Previewing changes no outfit, identity, memory or progression.
- Add to On this Mac explicitly retains the recipe on this Mac. The Alpha collection holds eight exact designs. Duplicate adds do not write another record.
- Equip applies the item for the visit. Wearing now and Next visit show the current and saved outfits separately, including a saved empty outfit. Review saved choices opens the existing preference controls; Save preferences keeps the outfit. A kept personal staff gesture overrides the creator default; Forget restores that design's default.
- Create variations using five palettes, three crown shapes, either decoration or pointing, and bounded pace/sparkle/hold choices. No arbitrary code, images, remote URLs or model prompts are imported.
- Recipe review explains missing names, oversized text, unsupported revisions and disallowed line breaks or control characters. An empty description remains allowed. Valid recipe previews explain that supported local choices do not verify creator or license declarations; a valid variation can be added without becoming registered. The review is computed from the existing validation rules and adds no fields to recipe exports or saved profiles.
- Import a local JSON recipe (maximum 4 KB) for review before Add. Feedback stays inside the sheet; Make a variation dismisses review before revealing Create. A full collection explains the limit and disables Add while keeping variation/export available. Removal remains in On this Mac, avoiding a second confirmation behind import review. Export shares the design and declared license only. It does not share private memory or companion identity, issue an edition, or transfer ownership.
- Use in Work together appears for the exact equipped, collected pointing recipe. It opens the existing working copy; selection and Point with staff remain deliberate actions. It does not capture a new source, call a model, automatically equip a different item or invent a passage. Decorative items cannot use this shortcut.
- Unequip refreshes feedback and changes this visit only. The next-visit outfit remains saved until explicitly updated or forgotten. A known external profile conflict or recovery block makes the next-visit label unavailable until a successful write or reload verifies it again.
- Remove atomically removes the recipe and any saved equipped reference, then clears a matching current outfit after the write succeeds. A conflicting or failed write preserves the prior collection and outfit.

## What registration means

| State | Current meaning | Canon effect |
| --- | --- | --- |
| Unregistered design | A new or edited recipe that does not exactly match the bundled approved catalog. Creator and license text are declarations. | Zero official battle modifiers, rewards, rankings or progression. |
| Registered local Alpha design | Every recipe field matches one of three bundled catalog entries in `archi-local-alpha-registry/v1`, for `archi-local-item-actions/v1`. | No Arena effect is approved in this release. |
| Production registered item (future) | Reviewed exact version with authenticated creator/rights, compatibility, assets and supported effects. | Registration alone grants no game effect. |
| Canon-approved game profile (future) | Registered version separately approved for a named ruleset/mode, with costs, limits, balance and counterplay. | Only those approved effects may count in that ruleset. |

A SHA-256 design fingerprint binds exact recipe content. It is not an owner UID, signature, NFT, market price, scarcity proof or Hampton Designed endorsement. An imported `registered`, `owner`, `power`, `script` or other unsupported field is rejected. Renaming a creator Hampton does not register a recipe. Modifying any field changes its fingerprint and loses a bundled exact match. Copying an exact bundled recipe remains the same freely copyable design, not a newly issued edition.

The native catalog returns an empty canonical-effect list for every item. The Unity Arena does not consume these recipes as loadout/stat inputs. Unity Area offers Companion and Arena destinations. This is a local non-effect boundary, not server-authoritative multiplayer enforcement. Future official play must validate signed registry versions and ruleset-specific loadouts before accepting an event; sandbox outcomes cannot be retroactively promoted by registering an item later.

## Persistence and continuity

`NativePreferenceDocument` advances to v5 with `itemLibrary`; v2–v4 and bare preferences still load with no disk rewrite until an explicit save. An equipped custom design must exist exactly in its library. The existing 64 KB profile cap, duplicate-key checks, file conflict comparison, atomic replacement, backup/restore and rollback stay authoritative. Item-only saves remain on disk. Lessons-only export excludes the library. Saved & this visit explains collection versus outfit retention.

The equipment identity includes the recipe digest, invalidating stale artwork/cue bindings when a design changes. Decorative items cannot activate pointing. A bounded label keeps the native/embedded artwork contract within 80 UTF-16 units without splitting visible characters. Seed/body continuity, local-first assistance and appearance choices remain in their existing owners.

## Earlier evidence and limits

Current checkout: full Swift suite passed 629 XCTest cases (32 skipped, zero failures) and reported 234 Swift Testing tests with the existing installed-worker opt-in skip. New tests cover strict recipe exchange, claimed registration, digest binding, palette/crown rendering, decorative activation, restart, equip/Save, atomic removal, conflict protection, older saves and actual backup restore/undo. These counts overlap the focused runs.

A hidden actual Marketplace view rendered legibly at 630×500 with no model calls or profile/identity changes. Native SwiftUI accessibility proxies were unavailable for the hidden panel; that acceptance is explicitly skipped. Full keyboard/VoiceOver, import/save-panel interaction, creator flow clicks, long-session use and another-Mac installation remain unqualified. No live LLM request was made. Build/staging evidence is recorded in `output/marketplace-increment-2026-09-14/`.

The existing [website marketplace guide](https://archi-it-begins-when-you-do.channelph.chatgpt.site/marketplace) links [public source](https://github.com/cr8ph8/ARCHi), explains the technical and proposed stewardship foundations, and separates local items from production registration and later Arena. Audience remains owner-private. Commerce, wallets, NFTs, transfers, creator submissions and popularity rankings are not enabled.

Delivery: [public source commit 6fd91a9](https://github.com/cr8ph8/ARCHi/commit/6fd91a954fc1a089d3de418753fa9f7ef0de86ba) pushed and remote manifest verified. Exported focused tests: 44 cases, two opt-in skips, zero failures. Site version 9 deployed; authenticated live page includes the marketplace, canon rule, GitHub link and foundation text. Native Review candidate built, plist checked and strict signature verified at `/private/tmp/archi-desktop-candidate-501/ARCHi Development Review.app`; installed/open apps preserved. Exact IDs and evidence are in `output/marketplace-increment-2026-09-14/delivery.json`.

## Marketplace interaction polish — 14 September 2026

The focused contract run passed **65 tests, zero failures/skips**. Eleven new outfit tests cover current/saved distinction, unrelated setting changes, Save opt-in off, forget, removal, store recreation, unreadable profiles, external edits and nonregular file replacement, recovery readback, exact equipped-item checks, stale actions and shutdown. Existing package, equipment, atomic collection, gesture-store and recovery-integration tests are included in that count.

Two **visible native interaction tests passed with zero failures/skips**, using a disposable profile and actual SwiftUI/AppKit controls. At 880×640 the test followed decoded import review → Make a variation → Create → Add → Equip → Work together, confirmed the real document body and NSTextView-selected passage, then used the native Remember/Save controls. Unequip changed the current label while preserving the saved next-visit outfit; a fresh store loaded the retained item and synthetic KIN identity. The 630×500 collection-limit test exercised disabled Add, inline explanation and the variation handoff. No model or capture calls occurred and no Arena view was loaded.

The initial harness run failed on native sizing, accessibility role lookup and view-update timing; these were corrected before the passing run. This is native accessibility-action testing and store recreation, not full keyboard/VoiceOver traversal, native Open/Save file-panel acceptance, an operating-system process restart, or ordinary-day use. Image artifacts are native view-cache captures and can omit composited layers; they are not a complete visual sign-off. Evidence: `output/marketplace-polish-2026-09-14/`.

Delivery for this polish: Development Review compiled and staged with plist and strict ad-hoc signature checks; the prior candidate bundle, installed app and active session were preserved. The separately exported public source compiled and passed 23 marketplace persistence/outfit tests with zero failures or skips. The historical Alpha tag, Arena pause and owner-private site remain unchanged.

The polish is published at [ffee7ea](https://github.com/cr8ph8/ARCHi/commit/ffee7ea9e77632de7cb13d816bff85dc498d9c1a). Remote main and its exact source manifest were verified; the public working copy is clean. Delivery receipt: `output/marketplace-polish-2026-09-14/delivery.json`.

## Unified native workspace — 16 September 2026

Marketplace now uses the shared workspace surfaces and cyan accent, with the current companion and both outfit lifetimes at the top. The preview reads the existing presentation form, appearance recipe, natural variation, equipment, light expression, and motion preferences. Browsing does not create another individual or change the worn design. Review saved choices opens the existing memory controls; Unity Area opens the existing Unity workspace without starting a player or publishing a presentation snapshot.

Discover and My items use centered previews of the existing equipment artwork. The selected design has an explicit visual and accessibility selection state, and an equipped tile says Wearing now. Wide content areas place the catalog beside its details; narrower windows stack the same controls. Create has labeled recipe fields, a live local artwork preview, grouped appearance/action controls, and a separate recipe review. The registration and recipe-export boundaries remain intact.

Two browsing defects were corrected: a filtered-out design no longer leaves its detail or Add action visible, and the first recipe added while an empty collection is open immediately becomes the visible selection. Clearing search restores the catalog. Switching between Discover, My items, and Create clears the prior page's search so it does not hide the destination's contents.

The final focused run passed **46 tests, zero failures/skips**, including **three visible native interaction tests**. It exercised the search field's actual native editor, the native segmented control, and SwiftUI accessibility actions. Checks covered filtered-result selection, no-result action removal, clear search, first collected item, full-collection review, decoded import → variation → Create → Add → Equip → Work together → Save preferences → Unequip → Unity Area. The tests preserved synthetic companion identity, current/saved outfit separation, local working-copy context, and profile bytes across navigation. Restart retention was checked by recreating the store. Assistant call counts remained zero; Unity presentation sharing and Arena loading remained inactive. The final run included the workspace navigation fix and emitted no publishing-during-view-update warning.

The first native attempt skipped because SwiftUI's accessibility proxies had not initialized. The fixture now queries only its own process through the public accessibility client API. Initial search-fixture attempts were corrected to use the native text editor and segmented control action; the final combined run passed. These are native control and disposable-profile checks, not full keyboard/VoiceOver traversal, native Open/Save file-panel acceptance, an operating-system process restart, or another-Mac installation.

Source: `desktop/Sources/ARCHiDesktop/MarketplaceWorkspace.swift`, `MarketplaceCompanionCard.swift`, `MarketplaceCreatorForm.swift`, and `MarketplaceItemPreview.swift`. Evidence and captures: `output/unified-workspace-2026-09-16/marketplace-native/final/`. Verification receipt: `output/unified-workspace-2026-09-16/marketplace-native/verification.json`. This increment is local code and evidence; the historical publication entries above do not describe its publication state.


## Creator catalog and consolidated native UI — 16 September 2026

The native Marketplace now separates **Discover**, **On this Mac**, **Account library** and **Create**. A compact companion card keeps current and next-visit outfits visible. Home presents concise Companion, Unity Area (Companion and Arena), Marketplace, Work together, memory and graph destinations. Related Appearance/Growth and Settings tabs use the existing destination owners; navigation does not launch Unity, connect a provider or save a profile.

The creator system uses the persistent development service in `marketplace/`:

1. Start it with an explicitly chosen private database path using `python3 -m marketplace --database <private-directory>/marketplace.sqlite3`. The default endpoint is `http://127.0.0.1:47831`; the native connection sheet also accepts another explicit 127.0.0.1 port. Constructors and workspace navigation perform no catalog request.
2. Choose **Connect & sign in**, connect the catalog, then create an account or sign in. Account creation and sign-in remain separate. Passwords are not retained by the client; the bearer session stays in memory and is revoked by Sign out. Authentication establishes the local publisher account, separately from the recipe's declared creator credit and license.
3. Create a recipe, enter attribution/source and a distribution-rights declaration, then **Save listing draft**. **My listings** supports edit, explicit Publish, Archive and version history. Edits create immutable draft versions while the previous published version remains in the catalog. Publishing or archiving requires a separate deliberate action. Optimistic version conflicts ask the author to refresh and reopen the latest version.
4. In Discover, search the creator catalog and **Add to account library** to acquire an exact published version. Included native recipes remain available independently. The catalog and local collection do not present duplicate search controls when connected.
5. In Account library, **Download & review** fetches the exact version. The client checks the raw closed recipe schema, duplicate keys, byte cap, computed fingerprint and response fingerprint header. Review stops before installation, including when a download finishes while the Marketplace is closed and the user returns later.
6. **Add on this Mac** uses the existing atomic eight-design collection owner. **Equip** remains a separate visit-only action; saving preferences retains the next-visit outfit. Acquiring, publishing, signing out or navigating does not change the companion's identity, memory, local equipment or profile.

Acquired snapshots survive listing edits and archive, and remain downloadable after signing in from a new client session. Creator history keeps recipe/provenance/status snapshots immutable; `publishedVersion` is the listing's current live-version pointer and can exceed an older snapshot's version.

The client sends an idempotency key with each listing/acquisition mutation. A transport interruption, invalid success response or service failure retains the exact request for **Retry the same request**. An unrelated failing read cannot erase recovery. Only that request's confirmed success or definitive 4xx rejection closes it. Request recovery and session credentials are memory-only; after quitting, sign in and refresh the service state before resubmitting uncertain work.

Publishing here makes designs discoverable in the running development service. It does not provide Internet hosting, moderation operations, verified rights, production account recovery, paid transactions, scarcity, registration or Arena effects. No local recipe can introduce executable code, arbitrary assets or private companion data into a catalog package. Public deployment remains a separate release task.

The focused combined run passed **44 XCTest cases, zero failures/skips**: nine client/recovery/date contracts, four visible native Marketplace workflows, eleven outfit tests, thirteen persistence tests, three presentation tests, one real HTTP/SQLite lifecycle, one Unity Area layout test and two Home navigation tests. The native creator test activated actual account, draft, publish-confirmation, acquisition, download, admission and equipment controls. Home checked 880×640 and 1280×820, including Companion Appearance→Growth and Settings Connections→Conversation→Comfort→Advanced, with profile, unsent draft and working-copy state unchanged. No provider calls, real-person profiles, installations or public publication were involved.

Evidence, failed attempts and captures are retained in `output/unity-arena-restoration-2026-09-16/native-polish/`; the passing log is `completed-native-focused.log`, with `completed-marketplace`, `completed-home` and `completed-unity-area` captures. A separate Home navigation trace isolates a SwiftUI publication warning on Growth→Home. It persists after one bounded main-queue/render-settle check; both Home tests still pass. This is retained as a known native warning rather than changing general navigation scheduling solely for direct accessibility-action testing. Native control actions and view-cache images do not qualify full keyboard/VoiceOver traversal, file-panel acceptance, ordinary-day usage or another-Mac installation. Earlier dated publication and test entries above describe earlier source, not this local increment's release state.
