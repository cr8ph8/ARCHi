# ARCHi developer and participant access protocol

26 September 2026 · development alpha

ARCHi is the ARC Hampton Interphase. One native app owns the companion, preferences and reviewed work. Unity is its bundled presentation/play helper; the local catalog is a service process, not another companion.

Read the [current progress report](system-progress-2026-09-26.md). These instructions apply to [draft PR #1](https://github.com/cr8ph8/ARCHi/pull/1), not a released beta or a public game server.

For method outcome review, People records and the solo-action observer, follow [Everyday learning and world outcomes](everyday-learning-and-world-outcomes.md). Its delivery and interaction checks are tracked separately from the access instructions below.

## Available access

| Goal | Entry point | Requirement |
| --- | --- | --- |
| Included designs | ARCHi → Marketplace → Discover | Working native installation; no account/model call |
| Creator recipes | Marketplace → Connect catalog | Python catalog running on this Mac |
| Solo practice | ARCHi → Arena → Play Arena | Compatible bundled Unity player |
| Two-player game | Unity → 2 players · M | Two people sharing one Mac/keyboard |
| Internet joining | Not implemented in the native Unity route | Transport, pairing, hosting and reconnection remain |

## Marketplace: included designs

1. Open **Marketplace → Discover**, select a design and review its preview, credit, license and action.
2. Choose **Add on this Mac**. In **On this Mac**, select it and choose **Equip**.
3. Equip changes this visit. For later visits, choose **Review saved choices**, review the outfit and **Save preferences**. Check **Wearing now** and **Next visit** separately.

The collection holds eight designs; repeat additions are idempotent. Preview, download and acquisition do not equip. Removal clears current/saved outfit references after confirmation. Companion identity and development stay with the existing profile.

## Marketplace: local creator catalog

From the repository root, with Python 3.11+:

```sh
python3 -m marketplace --database "$HOME/Library/Application Support/ARCHi/Marketplace/development.sqlite3"
```

This creates an empty private SQLite database when absent. Reusing the path retains accounts, listings and account libraries. Keep the process running while using the catalog; Ctrl-C stops it. No additional Python runtime packages are required.

Optional read-only connection check:

```sh
curl --fail --silent --show-error http://127.0.0.1:47831/v1/health
```

Expect service `archi-marketplace`, API version `1`, mode `development` and `commerce:false`. Health alone does not establish a successful user workflow.

1. In Marketplace, choose **Connect catalog**. Enter `http://127.0.0.1:47831` without `/v1`; select **Connect catalog** in the sheet.
2. Choose **Create account** if needed. Usernames have 3–32 lowercase letters, digits or underscores and start with a letter; passwords have 12–128 characters.
3. Creation does not sign in and clears the password field. **Enter your password again, then select Sign in.** Choose **Done** if the sheet remains open.
4. In **Discover**, search published recipes and choose **Add to account library**.
5. In **Account library**, choose **Download & review**, review the exact recipe, then **Add on this Mac**. Equip and next-visit saving remain separate.

Accounts belong to this Mac's catalog, not GitHub or an Internet identity service. The session stays in memory; sign in again after quitting ARCHi. If the port is busy, start with `--port 47832` and enter `http://127.0.0.1:47832`. The client only accepts explicit IPv4 loopback endpoints.

### Create, publish and recover

Sign in and open **Create**. Fill in the design, creator credit, license and distribution-rights declaration. Choose **Save draft**, review it in your listings, then **Publish** and confirm the named design. Edits create a new draft version while the previous published version remains visible until deliberately replaced. Archive is separate.

Publication means visibility in this local catalog. It does not provide Internet hosting, verified ownership, payment, scarcity or Arena effects. Recipes are bounded JSON data, not executable packages or arbitrary asset/model-prompt installers.

After a timeout, use **Try again** for the retained request rather than submitting a duplicate. If ARCHi quit during an uncertain operation, sign in and refresh listings/library before resubmitting. Do not delete the database to fix connectivity.

See the [API contract](../marketplace/API.md), [native Marketplace](native-marketplace.md), [account UI](../desktop/Sources/ARCHiDesktop/MarketplaceAccountView.swift) and [request owner](../desktop/Sources/ARCHiDesktop/MarketplaceCatalogStore.swift).

## Arena: enter and join a local game

Arena has two activities: **Companion practice** for Unity rounds, and **ARCHi Trials** for native Pattern Trials, interactive local ARC3 games and retained results. Both ARC entry points share the existing Reasoning owners. See [ARCHi Trials in Arena](native-arena-arc.md) for loading a task, selecting an environment, budget controls and evidence limits. Browsing the page starts nothing.

1. Open **PLAY & CREATE → Arena → Play Arena**. **Window → Play Arena** uses the same action; **Window → Arena** opens the page without launching.
2. If the companion is hidden, choose **Show & play**. A temporary **Practice roster** can be used without creating/replacing a saved companion. The separate Companion room requires a saved companion.
3. Focus Unity's Arena window. Select **2 players · M** or press `M` for two people sharing this Mac. Player 2 is the session-only guest **ECHO**; no second account or invitation is required.
4. Each seat locks a move. The paired round resolves after both choices arrive. Signature requires Spark.
5. Use **End session** in native ARCHi to close the helper.

| Action | Control |
| --- | --- |
| P1 Pulse / Guard / Signature | `1` / `2` / `3`, or labeled buttons |
| P2 Pulse / Guard / Signature | `J` / `K` / `L`, or P2 buttons |
| Solo/two-player switch | `M`; paired mode shows **Solo practice · M** |
| New bout | `N` / **New bout · N** |
| Return to companion | `B` |
| Stop motion | Escape; closes Laws first if open |
| Laws in solo mode | `L`; this is P2 Signature in paired mode |

Mode changes and new bouts reset the temporary match. Shortcuts need Unity focus; Command/Control/Option-modified keys are ignored. Stop/return does not terminate the native session. Unity practice does not grant saved growth, rankings, Marketplace rewards or canonical item effects.

### Show and save solo practice outcomes

Return to native **Arena → Practice outcomes** after solo moves. The summary shows retained action counts and their effects. **Save practice report…** exports a frozen JSON window, including sequence/bout IDs, observation time and retained/missed/retired coverage. Save before **End session**, which clears the in-app observations. No profile notes or companion identity are exported. Use **Try a move together → Track this suggestion** to bind Hampton’s conditional advice to the next observed solo input. Paired outcomes and automatic native action dispatch are not connected; a matched suggestion is not evidence of improved performance. See [the advice contract](native-arena-advice.md). See [practice report scope](native-arena-practice-report.md) and the [investor demonstration](investor-evidence-walkthrough.md).

### Arena troubleshooting

Choose **Set up Arena → Advanced**. Use **Use included Arena** when available, or **Choose Arena app…**, then **Check again**. Read the displayed reason. Missing players, incompatible Seed/outfit capabilities or failed acknowledgment require a compatible build; do not reset the companion to bypass them. **Return to Arena** brings an acknowledged session forward.

Arena does not require Qwen/Ollama, Marketplace service/account, payment or cloud inference. Unity Editor is only needed to build a player. These instructions are source-reviewed and backed by retained local keyboard evidence, not a fresh two-human playthrough.

There is no native online join link, room code or second-device lobby. **Relay** is a local puzzle, not a multiplayer network relay. The older browser game remains in source, but production native ARCHi disables that embedded route and does not bundle it. Browser Journey-saving instructions do not apply to session-only Unity practice.

Source: [native entry](../desktop/Sources/ARCHiDesktop/ArenaEntry.swift), [workspace/setup](../desktop/Sources/ARCHiDesktop/UnityWorkspace.swift), [local match contract](../unity/ARCHi/Assets/ARCHi/Runtime/ArenaMultiplayerSession.cs).

## Build or update the one app

The active source is a draft branch; main/historical releases may not include it:

```sh
git clone --branch codex/desktop-unity-alpha-20260918 https://github.com/cr8ph8/ARCHi.git
cd ARCHi
swift build --package-path desktop
```

Use macOS 14+, Swift 6 and Python 3.11+ for catalog work. Swift compilation does not install the complete app. Node/npm support retained web tooling; the pinned ARC replay runtime is not an Arena entry requirement.

**Fresh-clone blocker:** some current Liminal/Proto/KIN artwork is withheld pending redistribution qualification. The public branch cannot reproduce the complete installed desktop/Unity presentation. Review [alpha qualification](ALPHA_VALIDATION.md), [asset attribution](../ASSET_ATTRIBUTION.md) and [third-party notices](../THIRD_PARTY_NOTICES.md). Do not suppress missing-asset checks or redistribute private assets. No notarized download is supplied by this branch.

The native installer requires a compatible Unity player. Existing installs can reuse the bundled helper; first installation requires an explicitly qualified player. Export unsaved work, save wanted preferences and quit ARCHi before staging/installing. Do not run old Preview/Review apps alongside it.

Stage without installing or launching, choosing a new staging directory:

```sh
bash script/build_and_run.sh --stage-only \
  --stage-dir /private/tmp/archi-candidate-01 \
  --unity-player /absolute/path/to/qualified-player.app
```

The player path is a placeholder, not a download. After qualification, deliberately update the canonical app:

```sh
bash script/build_and_run.sh --unity-player /absolute/path/to/qualified-player.app
```

The normal command installs and launches `/Applications/ARCHi.app`. `--review` and `--install` are aliases for that same app. `--build-only` still installs but suppresses launch; use `--stage-only` for staging. `--verify` additionally runs the native suite and is not required merely to enter Marketplace/Arena. Development signing is not notarized distribution.

### Unity development

The project is `unity/ARCHi`; the wrapper pins Unity **6000.5.4f1** with macOS standalone support. Once required assets are admitted, close any Editor owning the project and finish source edits before:

```sh
bash script/build_unity_port.sh \
  -archiBuildOutput "$PWD/output/unity-port-2026-09-16/ARCHi Arena-dev-01.app"
```

Use a new `.app` below `output/unity-port-2026-09-16`; existing output is refused. Inspect the build receipt and exact path. Native packaging requires the proper bundle identifier/protocol and deep/strict signature validation. Build success alone does not establish signature qualification, native handoff or input acceptance. Identity and saved development remain owned by native ARCHi.

## Contribution and support protocol

1. Inspect the current source, instructions and evidence; preserve authored work. Use a `codex/` feature branch unless the maintainer specifies otherwise.
2. Extend the existing owner: native companion/preferences, catalog records, or session-only play. Do not create another profile or count a research formula as an implemented consumer.
3. Preserve proposal → review → explicit commit. Bind source, methods, outcomes and costs to their actual versions. Acquisition, equip, play success and learning are separate events.
4. Check the changed behavior narrowly. Catalog mutations require retry/idempotency and version-conflict evidence; Arena changes require input/focus/exit checks. Documentation needs command/link checks, not a puzzle campaign.
5. PRs describe the concrete change, source/build identity, checks and limitations. Keep personal profiles, databases, tokens, private papers, model weights and raw activations out of GitHub.

Use [GitHub issues](https://github.com/cr8ph8/ARCHi/issues) with the source commit/build receipt, macOS/tool versions, exact steps, expected/observed behavior, local mode, restart behavior and a redacted error/screenshot. Do not upload credentials, private documents or profile directories.

Before remote participation is advertised, implement authenticated discovery/invites, authoritative match state, duplicate/replay protection, reconnection/disconnect rules, version negotiation, consent/privacy and hosting. Production Marketplace also needs authentication recovery, moderation/rights operations and deployment safeguards. Changing a loopback URL does not supply these features.
