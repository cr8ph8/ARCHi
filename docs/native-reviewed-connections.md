# Reviewed connections between knowledge pages

29 September 2026. Hampton Stack memory and retrieval integration in the existing desktop app.

## Use it

In **Memories → Knowledge pages**, open a reviewed page, expand **Connections**, and choose **Connect a page…**. Choose two current reviewed pages, the direction, and **Supports**, **Contradicts**, or **Depends on**. Inspect both pages' exact passages and explain the connection. **Save draft** retains the declaration; **Mark link reviewed** is a separate action.

The connection appears at both endpoints, including its direction, rationale, version and review state. **Revise link…** creates a new draft; **Withdraw link** removes it from suggestions while retaining history. A withdrawn identity cannot be revived. Source or page corrections require explicitly choosing fresh endpoints and reviewing again. An open connection draft is protected during navigation, profile switching, restoration and Quit.

**Find connections in your reading** returns word matches first, followed by related pages one link away from word-matched pages actually displayed. Each related result shows the reviewed declaration and its direction. **Open page** rechecks its exact version and link. **Use in local chat** remains an explicit selection on the existing page inspector; Send is still separate. The link is a navigation explanation, not automatically added model context.

Activity map adds directed edges labelled **declared supports**, **declared contradicts**, or **declared depends on** only while both endpoints and the reviewed declaration are current. Open either page to inspect the rationale and history. Graph filters do not change stored bindings.

## What is retained

`KnowledgePageLink` contains a UUID, revision, two exact page bindings (UUID/revision/SHA-256), relation kind, user-authored rationale, draft/reviewed/withdrawn state, timestamps and an explicit review event. The endpoint pages own exact source anchors; links do not duplicate private source text or introduce another memory store. The author is the current user's declaration through this local editor; this is not a multi-user signed authorship system.

The same `ReadingSourceLibrary` journal stores pages and connections. Reading old v1–v4 archives causes no migration writes. The first connection save writes v5. Historical versions remain append-only, with at most 128 link versions and one reserved withdrawal slot per active link. Rationales are limited to 2,048 UTF-8 bytes. Existing source, page and 8 MiB archive bounds remain in force. Concurrent disk changes, malformed histories, forged endpoint bindings and duplicate review identities fail closed.

The existing five-file companion backup includes connection versions in the reading library and reports their count. **App rollback is not data rollback:** after creating a v5 library, a pre-v5 app cannot read it. Before intentionally downgrading, preserve current work and use the existing reviewed recovery flow with a compatible pre-link whole-profile backup. Never silently replace later authored data with an old backup.

## Operational rule

For a declaration `e = (a, relation, b)`:

```text
usable(e) = exact latest reviewed declaration
         AND exact latest reviewed page a and page b
         AND all endpoint passages and derivation parents current
         AND any endpoint person-record dependencies current
         AND source-library disk snapshot current
```

Search retains its existing lexical score. Related hits receive no lexical score and never claim confidence or entailment. Let `L` be admitted lexical page hits and `E` current reviewed declarations. One-hop neighbors are endpoints of edges touching `L`, excluding lexical candidates and duplicates. They do not become new expansion roots. Cycles therefore do not cause recursion. Combined results remain bounded to 12 hits and 16,384 encoded bytes, including connection metadata. Whole hits are omitted rather than clipping quotations. Omission counts are visible.

## Research placement and limits

This implements exact dependency navigation and correction-aware retrieval for Hampton's source-addressed memory layer. It connects the [research intake's first two priorities](research/2026-09-29-memory-learning-selection/README.md) to native runtime consumers. It is a deterministic engineering adaptation, not a trained WFM reproduction, model-weight learning, semantic verification, or validation of Hampton's full theoretical framework. Reviewed support can still be mistaken; contradictions are shown for inspection rather than resolved automatically.

The iPhone keeps its current app and storage contracts. Linked-library transfer, learned graph propagation, training exports and expanded route/context receipts remain separate work. No provider access or model inference is required to author, review, search, graph or back up these connections. Current delivery evidence is in the developer ledger; a build or focused check alone does not establish full installed interaction acceptance.
