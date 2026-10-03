# Local chat with reviewed knowledge pages

ARCHi can use explicitly selected, user-reviewed claim and concept pages as context for local Qwen chat. This connects authored memory to ordinary reasoning through the existing companion, source library and request owners. It adds no separate chatbot, vault or model-training service.

## Use a page

1. In Memories, open a reviewed page whose supporting passages are still current.
2. Choose **Use in local chat**. Repeat for up to four pages. ARCHi opens Chat and shows each selected page and its version. Selection alone makes no request.
3. Enter the question and press Send. The question uses the configured local Qwen reasoning route. **Choose pages** returns to Memories; **Detach** removes the page context and clears the earlier temporary page conversation.

The current shared document and selection remain in the app, but their text, name and selection are omitted from this page request. Selected reading copies are not independently added alongside page context; the page's exact anchored passages supply its source material. The normal local personal context and eligible Chat lessons may still accompany the question. Detaching pages allows the normal shared-document flow to resume.

## Routing and size boundaries

`KnowledgePageContext` accepts one to four distinct reviewed pages. Its **16,384-byte UTF-8 limit** covers the encoded knowledge block, passage text, metadata, guidance, JSON escaping and the accompanying citation declarations. This is the knowledge-context limit, not a claim that the entire request fits in 16 KiB. Over-limit selections block Send until fewer or shorter passages are chosen; neither note text nor evidence is silently clipped.

Page context uses local Qwen only. Codex, Compare, external fallback, pointing and document-revision requests are blocked while pages are selected. Missing local model readiness is a local availability problem; it does not authorize an external retry. Existing task budgets, deadlines, cancellation and result-admission checks remain in place.

## Exact provenance through the reply

A page binding contains its UUID, revision and digest of the complete canonical page, including its anchors and review event. Each anchor identifies an exact retained source UUID/revision/text digest, UTF-16 range and quoted-byte digest. Request context adds the current exact quote; page storage itself does not duplicate source prose or original file paths.

The source library and selected page versions must be current on disk before dispatch. Request receipts capture both page and source dependencies. The existing owner checks them again while admitting the answer, on completion, and before dependent follow-up context or lessons are reused. Revision, withdrawal, source replacement, source forgetting or an external writer changing the library makes the earlier dependency unavailable. An old answer cannot authorize reuse of a changed page; choose and review the current version instead.

Model input distinguishes the authored interpretation from the quoted passages and gives each a citation identifier. It instructs Qwen to treat both as source data, identify missing or contradictory support, and follow the current user's request. Citation membership verifies which supplied reference was named; it does not establish that the passage proves a claim.

## Memory and development boundaries

Selecting a page or accepting a reply does not establish a fact, train model weights, keep a lesson, certify a method or award companion development. Current page-dependent replies are excluded from the existing useful-reply and lesson-helped development admission.

The user may separately review and **Keep** a lesson from a completed page answer. Its retained origin includes exact page and source bindings. The lesson is **Chat-only**, applies to Chat while its exact dependencies and expiry remain current, and becomes unavailable if those dependencies change. It does not enter document-revision methods through this route. Eligible kept lessons are considered in their saved order; any that would exceed the combined four-page/eight-source dependency limit are omitted with a visible explanation. The saved lesson is unchanged. These checks apply to supplied context even when a model does not cite every supplied page; uncited context is not treated as absent provenance.

Page drafts, reviews and withdrawals use the existing reading-source archive. Profile backup preserves that archive's source copies and full page history together; it does not save the temporary selected-page conversation. See [knowledge pages](native-knowledge-pages.md) and [backup and restore](native-desktop-backup-and-restore.md).

## Implementation and remaining scope

The source routes are `KnowledgePageContext.swift` for bounded request material and binding digests, `KnowledgePageIntegration.swift` for explicit selection/currentness, `CompanionStore.swift` for dispatch and lesson dependencies, `QwenAssistant.swift` for the local request, and `EvolutionIntegration.swift` for the development exclusion. `KnowledgeChatContextView.swift` exposes the selection before Send.

This increment implements explicit local use. Automatic semantic retrieval, automated page synthesis, model-independent entailment checks, cross-page reasoning certification and automatic promotion to reusable skills remain outside it. Source review and deterministic fixtures establish narrower facts than a real-model quality evaluation or an installed-app acceptance walkthrough; report those outcomes separately.
