# One ARCHi system

Open `/Applications/ARCHi.app`. Home, Ask ARCHi, Memory map, Work together, Marketplace and Arena are destinations inside that app. The companion name identifies the individual; it does not identify a second installation.

## Runtime ownership

| Need | Existing owner |
|---|---|
| Conversation, requests and chosen model route | Native ARCHi; Ask ARCHi and the Seed bubble share a draft and request lifecycle |
| Personal details, retained sources, linked pages and lessons | The selected native companion profile; local data stays outside the source publication |
| Document work and useful methods | Work together, reviewed Apply/outcome history and version-bound method records |
| Identity, appearance and development | Native companion owners; presentation alone awards no growth or permission |
| Companion room and Arena | Bundled Unity helper under the native session, with explicit play and inspection modes |
| Item creation and collection | Existing Marketplace services and native installed-item/equipment owners |
| iPhone | Separate platform client in the same product; transfer and feature parity require explicit qualification |

Local Qwen, the representation runtime, Unity and creative authoring tools serve these owners. Keeping a helper does not create a second companion. Do not import donor applications' profile stores, model brokers or shells wholesale. See [current status](system-status-2026-09-29.md) for which research consumers are operational and which remain unfinished.

ARCHi's local records are the canonical authority; WikiOS is a linked interface. See the [native authority and lineage map](native-authority-and-lineage.md) for exact owners, immutable task references, acquisition declarations and future plugin boundaries.

## Source and delivery

The primary authored workspace is the main ARCHi repository. The local `output/source-checkpoint-2026-09-25/publication-01` checkout is the curated draft-PR source. They have different purposes: authored work can contain pending art, iPhone changes, research attachments and private local outputs that are not ready for publication or installation.

Integrate a change into its existing owner, verify the affected behavior, then deliberately promote only its reviewed source. Use the existing guarded installer for delivery. Reopen the installed app normally when no update is needed. Do not rebuild just to open it, launch dated backups as extra personal apps, or use an older export checkout as the current source.

## Application backups

Normal updates reserve an inactive rollback at `~/Library/Application Support/ARCHiRecovery/Rollbacks` before replacing the current app. The destination must be private, have no symlink path components and be on the same filesystem. Replacement still requires a normal Quit and a verified candidate; failed promotion retains the existing restore path. Stage-only workflows keep their existing behavior. Nothing automatically prunes old builds.

A one-time cleanup moved 107 dated ARCHi rollback bundles out of Applications without deleting them. Their root directory identities, executable hashes and Info.plist hashes were verified after the same-filesystem moves. Only `ARCHi.app` remains at the top level of Applications. The dated `applications-relocation-2026-09-29.json` beside the backups maps every original path to its recovery path. Historical delivery receipts remain unchanged.

Recovery is deliberate: quit ARCHi normally, identify the exact compatible bundle and preserve the current app before replacing it. Verify the chosen bundle's signature and source identity. A binary downgrade may also require a compatible profile backup; newer reading-library data must not be opened casually with an older binary. App rollback copies do not contain or replace the live profile library. This local archive is not an off-device backup and moving files does not reclaim their disk space.

## Start here

- [Current system status and remaining work](system-status-2026-09-29.md)
- [Desktop operation](../desktop/README.md)
- [Ask ARCHi and private context](native-ask-archi.md)
- [Memory map and Showcase](native-memory-dashboard.md)
- [Marketplace and Arena access](developer-access-protocol.md)
- [Delivery ledger](../PROJECT_ACCOUNTABILITY.md)
