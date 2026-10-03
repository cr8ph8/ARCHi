# Native owners and next implementation sequence

Source inspected on 27 September 2026. This is a current-source audit; it does not requalify the installed binary, reproduce papers or change saved companion state. Paths refer to the existing desktop owner, not a replacement service.

## What is already connected

| Function | Source and current behavior | Remaining distinction |
|---|---|---|
| Source copies | [ReadingSourceLibrary](../../../desktop/Sources/ARCHiDesktop/ReadingSourceLibrary.swift) keeps explicit text copies and advances revisions on replacement (lines 77–104). Quotes resolve against current source bytes (126–141). | Replacement preserves historical digests, not old source text. [ReadingSourceSnapshot](../../../desktop/Sources/ARCHiDesktop/DocumentReadingPlan.swift) has id/title/revision/text (3–18), without typed origin or derivation metadata. |
| Structure and retrieval | [DocumentReadingPlan](../../../desktop/Sources/ARCHiDesktop/DocumentReadingPlan.swift) already follows Markdown heading ancestry, skips code-fence headings and bounds spans (292–349). It validates exact spans and coverage (121–164). [KnowledgeRetrieval](../../../desktop/Sources/ARCHiDesktop/KnowledgeRetrieval.swift) filters unreviewed, conflicting and stale pages; ranks lexical matches (75–143,185–195). | The September 18 proposal is partly realized. Full arbitrary-document outline support and trained semantic retrieval are different work. Lexical relevance is not entailment. |
| Correction and learning | [HamptonMemoryDependencies](../../../desktop/Sources/ARCHiDesktop/HamptonMemoryDependencies.swift) invalidates dependent answers and withdraws development credit (19–88). [DocumentProcedure](../../../desktop/Sources/ARCHiDesktop/DocumentProcedure.swift) separates source-bound candidates from procedures grounded in verified application and helpful feedback (238–368). | This dependency graph is not a general independent-origin graph. User usefulness does not prove factual truth or cross-task transfer. |
| Adaptive methods | [HamptonMethodOutcomes](../../../desktop/Sources/ARCHiDesktop/HamptonMethodOutcomes.swift) deduplicates record identities, retains corrections and ranks attributed feedback with a Beta(1,1) mean heuristic (33–84). | It is explicitly an ordering heuristic. Repeated uses of one lineage do not become independent scientific replications. |
| Numerical feedback and coupling | [HamptonNumericalDynamics](../../../desktop/Sources/ARCHiDesktop/HamptonNumericalDynamics.swift) computes bounded candidates, a potential field and typed effective-delta coupling. Document and reading adapters supply domain meanings. | These authored policy coordinates must not be renamed model probabilities or latent physics. A coupled change needs attributable outcome evidence to establish usefulness. |
| World actions | [WorldOutcome](../../../desktop/Sources/ARCHiDesktop/WorldOutcome.swift) checks action/session/sequence binding. [WorldOutcomeHistory](../../../desktop/Sources/ARCHiDesktop/WorldOutcomeHistory.swift) rejects rewritten observations and exposes missing records. [HamptonArenaAdvice](../../../desktop/Sources/ARCHiDesktop/HamptonArenaAdvice.swift) binds advice to the next actual observation (178–217). | History is bounded and session-only; matched action is association, not causal benefit. Paired reporting remains unconnected in [UnityPresentationConnection](../../../desktop/Sources/ARCHiDesktop/UnityPresentationConnection.swift). |
| Model path | [QwenAssistant](../../../desktop/Sources/ARCHiDesktop/QwenAssistant.swift) performs bounded inference through `api/chat` (166–190). [Separate reader research](../../../research/representation/gguf/task_reader.py) fits reader parameters against frozen-model activations. | No base-model weight-training route was found in the inspected desktop source. Reader calibration, retained methods and Qwen training are distinct operations. |

## Three next upgrades

### 1. Source origin and derivation — first

Extend the existing source snapshot/archive schema with orthogonal fields: authoring origin (`human`, `model`, `mixed`, `unknown`), acquisition kind (user copy, external publication, observed executor result), declared attribution, parent source/revision/digest references and review state. An external publication may contain generated material; do not force these dimensions into one mutually exclusive label. Existing sources migrate to unknown unless explicit provenance exists. Never infer human authorship from writing style or a pasted chat label.

Keep retained original revisions only under an explicit bounded retention policy; preserve correction/forgetting semantics and prevent deleted content from reappearing through a derivative. A hash can identify bytes after deletion, but it cannot reconstruct a missing source. Display unresolved evidence as unavailable. Distinguish source-lineage deduplication from actual independence: different URLs can repeat the same claim, while repeated observations can share a cause.

**Done when:** source → draft page → method → request receipt preserves origin and derivation; replacement/forgetting invalidates or qualifies descendants; migration stays unknown; no automatic profile import or training export occurs. A short focused integrity check is appropriate when implemented; no puzzle suite is required.

### 2. Retrieval evidence the user can understand

Use the existing Memories/Work together/Chat surfaces. Explain “current passage,” “matched these words,” “other sections were omitted” and “answer needs review” separately. Do not invent a numerical truth confidence from lexical rank. Preserve the current heading selector, and add richer outline adapters only for an actual supported input format. Unsupported answers should permit abstention or asking for the missing document.

**Done when:** one everyday document request exposes the actual retained spans, current versions and omissions; valid-but-irrelevant evidence remains visibly distinguishable from supported answers. Any later trained retriever must beat this baseline on independently authored questions at matched context/call cost before replacing it.

### 3. Common attribution and outcome presentation

Unify presentation of existing method and world receipts around candidate → applied action → observed result → review/correction. Share vocabulary and identifiers, without flattening distinct owners or creating a second canonical store. Retain unsuccessful, contradicted, cancelled and unknown outcomes. Show changed allocation, measured resource use, user usefulness, independently checked correctness and transfer as separate fields.

For Hampton demonstrations, the concrete story is: a named observation changes a typed coordinate; the controller changes a choice; an actual outcome is recorded; a later review can revise that influence. Use the existing numerical adapters and [Arena practice report](../../native-arena-practice-report.md). Causal benefit requires a matched comparison; a successful demonstration alone cannot supply it.

**Done when:** an inspector can follow one real everyday method and one world action through those records, including counterexamples and resource limits. An absent relationship or missing observation never renders as zero failure.

## Where these papers do not belong by default

They do not justify automatic Qwen retraining, activating an unqualified RepE reader, a new RNA feature, changing Seed identity/personality, awarding growth for generated summaries, granting marketplace items authority, or claiming that neural energy and measured hardware energy are interchangeable. Creative appearance remains authored expression. Research metrics can inform an experiment; they cannot rewrite source truth, user consent or action permissions.

This mapping covers knowledge, learning, representation, allocation, correction, world feedback and development evidence. It deliberately preserves the broader Hampton scope instead of reducing the work to a final gate. Source freshness and explicit authority support useful adaptation throughout the loop.
