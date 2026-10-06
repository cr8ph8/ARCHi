# One authored ARCHi source

> Publication note: references marked “local reference” are intentionally omitted from this curated snapshot. Their authored documents and receipts remain preserved in the main workspace; this page does not reproduce their evidence.

The main ARCHi workspace is the source of changes. The curated GitHub checkout is an outbound publication copy, not a second place to develop features. The native app continues to own profile identity, evidence, memory and reviewed outcomes. WikiOS, Unity and future device panels use those owners through explicit contracts.

## Local workflow

1. Edit the main workspace and read the applicable owner contracts. Preserve unrelated authored changes.
2. Review the actual diff and run checks for the affected boundary. A source build does not install the app or qualify every renderer.
3. Promote reviewed source to the existing publication checkout. Carry together callers, implementations, tests, resource contracts and Unity metadata. Exclude private profiles, research attachments, model weights and unapproved artwork.
4. Run `python3 script/check_source_parity.py --source /path/to/authored/ARCHi --publication /path/to/publication --policy docs/source-parity-policy.json`. Resolve missing or changed code. The policy permits only exact reviewed hash pairs for resource-pin transformations; it does not permit arbitrary divergent implementations.
5. Review every publication path, refresh `SOURCE_SHA256SUMS`, verify its complete tracked coverage and update the existing draft PR. Never publish the authored workspace's private Git history.

The parity check covers all top-level native Swift source/tests, the shared `ARCHiSpatial` source/tests and its package manifest, the desktop package manifest, retained TypeScript source, ARCHi Unity C#/shader source, and already-published script/vendor code. It does not certify source licensing, security, generated products, iPhone completeness or all documents. A new unpublished iPhone/authoring file remains visible in the local inventory, not silently classified as dead code.

## Workspace roles

| Location | Role |
| --- | --- |
| Main `ARCHi` workspace | Authoritative development: native, iPhone, Unity, authoring and local evidence. |
| `output/source-checkpoint-2026-09-25/publication-01` | Existing draft PR delivery checkout. Refresh from reviewed main source; do not author a parallel app here. |
| `output/github-alpha-preparation/source` | Historical clean distribution checkpoint; never the active publishing destination. |
| Archived ARCHi Desktop R1 | Locked donor under `ARCHi Recovery/retired-worktrees/2026-10-02/`; useful mechanisms require deliberate integration into current owners. |
| SigGraph Hackathon | Research donor and common Git database for R1 worktrees. Do not move/delete casually. |
| Retired ARCHi Product R1 | Preserved, locked worktree; no active development. |

These are preservation roles, not six shipping products. A directory may contain unique research or unfinished work without being a dependency of the native app. Remove code only after identifying its callers, data obligations, unique history and replacement; file age alone is not a deletion criterion.

## Current consolidation

**5 October 2026:** the single desktop 1.0 plan (local reference) and feature register (local reference) now govern consolidation sequencing. The October checkpoint preserves selected text source locally; it is not a complete independent backup. The current reconciliation receipt (local reference) records 38 exact code promotions into the local outbound checkout: 1,024 matching files, four approved resource-pin pairs and zero unexplained scoped differences. Its 1,802-row manifest covers every staged/tracked file except itself. This defines the reviewed source cohort. The developer ledger records its subsequent delivery status; the earlier receipt retains the pre-publication state. Earlier parity receipts remain historical. Preserve paused Unity/mobile work and all unique donor mechanisms. No feature retirement is authorized by a missing runtime caller alone.

### Historical 2 October reconciliation

The 2 October reconciliation brings publication's memory/evidence/method flow back into the main source, preserves the main source's Liminal structure/finish/light and WikiOS handoff, and promotes reviewed implementation back through the one existing draft. Native and Unity protocol changes travel together. Original authored and sanitized publication assets retain their own verified literal hashes.

Desktop R1 was relocated with `git worktree move` and locked as a donor archive after complete file/state preservation checks. A removed temporary-worktree registration referred to an already absent directory. Its branch and commits were retained. No live profile, original art, R1 repository or unique branch was deleted. The installed desktop app and physical phone are separate delivery gates; this source cleanup does not replace them.

See [contribution rules](../CONTRIBUTING.md), [security boundaries](../SECURITY.md), [native authority](native-authority-and-lineage.md), and the developer ledger for actual checks and remaining work.

The fresh-export allowlist now includes the shared Apple package and explicit native packaging helpers. Its bounded build-recipe dependency check rejects an omitted helper rather than exporting an incomplete recipe. This is not dynamic dependency resolution or blanket asset approval: the fresh main export still reports 79 unreviewed file-kind findings. Promote only the reviewed code cohort into the existing curated publication; retain its qualified asset transformations.
