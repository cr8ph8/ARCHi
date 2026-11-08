# Continue the peer change in local Codex

## Current state

The representation and peer change was implemented in a real local Linux checkout on `codex/peer-representation-admission`, based on public-source commit `ffee7ea9e77632de7cb13d816bff85dc498d9c1a`. That checkout is separate from the owner's Mac and may differ from the Mac's current authoring branch. It has not updated or installed the Mac app.

Codex CLI 0.167.0-alpha.4 was available and reported ChatGPT authentication in the implementation workspace. Its review runner failed during in-process app-server initialization with `Read-only file system (os error 30)`, including a retry using documented temporary SQLite/log paths. No Codex review result was produced. Authentication files, home settings and repository permissions were not changed. This is a runtime limitation, not a passing review or an approval rejection.

Open the **existing ARCHi folder** in Codex on the Mac. Use the following task with the proposed branch or patch available. Work in that project rather than replacing its source with the public snapshot.

## Task for Codex

Continue the local ARCHi particle/node/neural/pixel peer integration. Inspect the current working tree, branch and applicable project instructions first. Reconcile the proposed change with the existing local code and preserve unrelated work. The proposal's base is `ffee7ea9e77632de7cb13d816bff85dc498d9c1a`; do not assume it matches the current Mac project.

Read `CONTRIBUTING.md`, `docs/ARCHITECTURE.md` and `docs/PEER_REPRESENTATIONS.md`. The change adds five native source files: the typed representation domain, bounded observation directory, deterministic in-process gossip simulation, read-only work session, and native peer workspace. The existing owner gains session state, injected-clock accessors and a cancellation hook. Node Lab gains a second surface.

Review source/context freshness, scoped observation identity, evidence preservation, clock boundaries, cancellation and exact attempt admission. Confirm that repeated relays retain one evidence origin and cannot authorize work. The real inspector should receive only graph metadata and should retain accepted reports only in session memory. It must not change model weights, saved lessons, preferences, the working copy, the active companion or provider routing. Keep the offline fixture workers clearly distinct from real network peers and actual renderer/model output.

Compile and run the relevant tests with the Mac's existing Swift 6 and SDK:

```sh
script/test_representation_peers.sh
swift build --package-path desktop
swift test --package-path desktop --filter 'RepresentationPeerTests|CompanionPeerIntegrationTests|CompanionGraphTests|CompanionGraphIntegrationTests'
```

Resolve concrete failures and rerun the affected checks. In the native UI, inspect **Node Lab → Representations & peers**: verify narrow-window layout, keyboard access and readable observation details; inspect and accept the current graph; then prepare another inspection, change the source and verify that acceptance is refused. Advance the fixture rounds to inspect relays, duplicate receipts and expiry. Report observed behavior separately from unexecuted checks.

Use the project's existing build workflow after source validation. Preserve the current profile and running app; do not silently replace an installed build. Refresh `SOURCE_SHA256SUMS` for this checkout's final tracked files, verify complete coverage, and summarize the exact local path, commit, checks and remaining limits. GitHub synchronization is separate from applying and building the local project.

## Command references

OpenAI documents non-interactive local repository work with [`codex exec`](https://learn.chatgpt.com/docs/non-interactive-mode), and local change reviews with [`codex review`](https://learn.chatgpt.com/docs/developer-commands?surface=cli). A review is evidence about source, not a substitute for compiling the native app and observing its behavior on the Mac.
