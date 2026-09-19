# Validation scope for the unified source candidate

Status: code-only draft review. The current branch has separately exercised source checks below; withheld artwork and remaining acceptance gates prevent a complete release qualification.

The source preflight and its regression tests are new preparation tools. Its local fixture suite verifies safe exclusions, FBX inclusion, symlink rejection, location-only secret reporting, PNG metadata detection, overwrite protection, clean/dirty source gating, exact asset review, source checksums and source/evidence digest binding. Those tests do not qualify the ARCHi UI or Unity runtime.

Before promoting a candidate, record the exact source inventory digest, command, outcome, skips, limitations and SHA-256 of each actual evidence file:

| Gate | Required evidence |
| --- | --- |
| Web source | `npm ci`, proposed `npm run check`, and built asset checks in the isolated source copy; resolve any source-only command gaps |
| Native source | Clean Swift build and full native test result, with explicit opt-in/skipped test counts |
| Unity source | Pinned Editor build, bundled rig/resource/import validation, scene checks and player build receipt from the isolated source copy; `EvolutionFoundationValidation.Validate` must verify included runtime hashes and report missing private authoring copies explicitly |
| Native, Unity and Marketplace acceptance | Reviewed start/stop/reopen native-to-Unity session, same-individual snapshot continuity, malformed/stale/disconnected recovery, saved local collection/outfit behavior, keyboard/VoiceOver, reduced motion, smallest supported layout and resource use |
| Creator service | `python3 -m unittest discover -s marketplace/tests -v` in the exact isolated source; persistent account/session/listing/inventory lifecycle, authorization, native recipe fingerprint, bounded HTTP boundary and retry checks |
| Native creator marketplace acceptance | Native API client against a disposable real loopback service/database: account sign-in/out, save/edit/publish/archive, history, catalog search, exact-version acquisition/download, explicit local admission, duplicate/capacity/conflict/cancel recovery; retain the selected profile's ownership boundary |
| Release integrity | Current checksum manifest, reviewed code/assets/notices, no private records in files or promoted history, candidate-only metadata repairs with corresponding hash updates, and a clean identified candidate commit |

The development root has private research/accountability history and substantially untracked native/Unity source. A new release must be deliberately promoted to a separate source copy. Do not publish that root's entire directory or history. The current allowlisted source preparation includes FBX and metadata companions and excludes private creator databases; the old public promoter must not be used unchanged. The earlier source-candidate-03 predates restored Arena, creator service/client, later Seed/Proto work and additional native routes. Its pass receipts do not qualify this later snapshot.

Source preflight receipts cannot infer the correctness of a reviewer assertion from a log's hash. The receipt must be inspected. A pass is also not owner authorization to publish, a Beta declaration or proof of ordinary-day reliability.

Private authoring parity is separate from portable Unity source validation. The source packet omits `desktop/ArtSources`; the strict `EvolutionFoundationValidation.ValidateAuthoring` check should therefore fail for missing originals. Do not manufacture authoring parity by copying sanitized runtime files into the authoring paths. The local preparation receipt retains original/exported hashes and the exact metadata transformation separately.

## Separate signed-app release

The source package does not promise a notarized download. The current native build script uses local ad-hoc signing and development bundle identifiers. A distributable app still needs a chosen supported release bundle/version, appropriate signing and entitlements, verification of every nested Unity/helper component, notarization and ticket verification, another-Mac install/open, privacy permission recovery, update/rollback and an ordinary-use acceptance session. No distribution credential or signature is created by this packet.

## 18 September code-only draft

The public review branch deliberately omits these new-artwork paths and their Unity metadata. Full local-candidate native/Unity validation does not qualify this reduced artifact. Web-source and source-export fixture checks are independently exercised on this branch; art-dependent native tests and the full Unity build remain blocked here. The main branch and existing release tags remain unchanged.

- `desktop/Sources/ARCHiDesktop/Resources/CompanionArt/archi-ball-of-light-v1.png`
- `desktop/Sources/ARCHiDesktop/Resources/CompanionArt/archi-proto-blender-v1.png`
- `desktop/Sources/ARCHiDesktop/Resources/CompanionArt/hampton-liminal-garnet-v1.png`
- `desktop/Sources/ARCHiDesktop/Resources/CompanionArt/hampton-liminal-seed-v1.png`
- `unity/ARCHi/Assets/Resources/KIN/hampton-liminal-garnet-v1.png`
- `unity/ARCHi/Assets/Resources/KIN/hampton-liminal-garnet-v1.png.meta`
- `unity/ARCHi/Assets/Resources/KIN/hampton-liminal-seed-v1.png`
- `unity/ARCHi/Assets/Resources/KIN/hampton-liminal-seed-v1.png.meta`
- `unity/ARCHi/Assets/Resources/KIN/kin-arena-motion-v1.fbx`
- `unity/ARCHi/Assets/Resources/KIN/kin-arena-motion-v1.fbx.meta`
- `unity/ARCHi/Assets/Resources/KIN/kin-reference-v2.fbx`
- `unity/ARCHi/Assets/Resources/KIN/kin-reference-v2.fbx.meta`
- `unity/ARCHi/Assets/Resources/Proto/archi-ball-of-light-v1.png`
- `unity/ARCHi/Assets/Resources/Proto/archi-ball-of-light-v1.png.meta`
- `unity/ARCHi/Assets/Resources/Proto/proto-archi-v1.fbx`
- `unity/ARCHi/Assets/Resources/Proto/proto-archi-v1.fbx.meta`
- `unity/ARCHi/Assets/Resources/Proto/proto-archi-v2.fbx`
- `unity/ARCHi/Assets/Resources/Proto/proto-archi-v2.fbx.meta`
- `unity/ARCHi/Assets/Resources/Proto/proto-body.png`
- `unity/ARCHi/Assets/Resources/Proto/proto-body.png.meta`
- `unity/ARCHi/Assets/Resources/Proto/proto-character.fbx`
- `unity/ARCHi/Assets/Resources/Proto/proto-character.fbx.meta`
- `unity/ARCHi/Assets/Resources/Proto/proto-light-v3.fbx`
- `unity/ARCHi/Assets/Resources/Proto/proto-light-v3.fbx.meta`
- `unity/ARCHi/Assets/Resources/Proto/proto-light-v4.fbx`
- `unity/ARCHi/Assets/Resources/Proto/proto-light-v4.fbx.meta`

### Fresh checks and their scope

On this code-only branch, `npm ci --ignore-scripts --offline` and `npm run check` passed: 260 retained TypeScript, 28 ARC, 12 pinned replay, 11 boundary/trace and 10 PWA checks plus typechecking/build. Source-export fixtures: 32 passed. Marketplace service: 40 passed against disposable loopback state. `swift build --package-path desktop` passed; it does not establish runtime artwork availability. These checks ran on macOS arm64 with the local tool versions listed in the README.

The separate complete local candidate (manifest `3b84c206fc8f287ddc51474773a02c90e14fca26479b6623e785dad39ca0fe4a`) includes the withheld artwork. It passed 835 XCTest cases with 53 opt-in skips and zero failures, plus 258 Swift Testing tests. Its Unity build passed 7,771 battle-parity, 4,778 local-multiplayer and 97 personal-Seed assertions; 88 standalone runtime checks and ten real native-to-Unity handoff tests passed separately. These numbers describe overlapping, differently scoped suites. They do **not** claim full validation of this reduced public branch.

The installed local app separately passed M/two-player, first-choice wait, second-choice resolution and N/reset interaction. Actual mouse/two-human play, VoiceOver, sleep/wake, other-Mac installation, online multiplayer and release signing remain open. Initial export attempts exposed stale personal-Seed tests and checkout-name restrictions; their corrected versions are included. The final tracked-file scan excludes generated bytecode/logs and removes metadata from existing public PNGs without changing pixels. No new artwork license is inferred.
