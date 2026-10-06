# Hampton memory dependencies and linked knowledge

25 September 2026. Hampton Stack R2 L07 (memory/retrieval) and L06 (reviewed experience and reusable methods), through the existing native ARCHi owners.

## Current page connections — 29 September 2026

The earlier method-dependency work below is retained as its dated checkpoint. Native claims/concepts, source provenance and now [reviewed typed page connections](native-reviewed-connections.md) extend the same owner. The new guide defines current review, one-hop retrieval, correction and backup behavior; the earlier remaining-work table is historical.

## Installed mechanism

A completed passage-revision request now retains two different collections: all supplied lesson versions and the subset the model cited. Each reference includes lesson identity, revision and snapshot digest; it duplicates no private lesson text. A supplied lesson can influence an answer without being cited, so method availability follows **all supplied versions**. Learning credit still requires the existing explicit review; supplying a lesson earns none.

Keeping, revising and reusing a method checks complete provenance, its helpful applied source result, exact current lesson versions, scope, expiry, source bindings and ancestor methods. A changed, withdrawn or expired dependency makes the method unavailable. History remains inspectable. Earlier records without supplied-context provenance remain readable and require fresh reviewed work before method reuse; missing provenance is never converted to an empty dependency set.

Feedback admission also checks the current journal on disk and the exact retained record. An older cached Helpful record cannot enter development review or update Usage after another writer corrects it. Existing native numerical feedback and coupling remain distinct from graph presentation.

## Operational definition

Let D(r) be exact lesson versions supplied to request r, C(r) its model-cited versions, and A(m) the originating request records of method m and its ancestor methods. New records enforce C(r) ⊆ D(r). An absent D(r) means unknown historical provenance; an explicitly empty set means no lessons were supplied.

For this document path:

```
usable(m) = current_method_history(m)
         AND helpful_applied_origin(m)
         AND no_retained_counterexample(m)
         AND for every r in A(m): complete_provenance(r)
         AND for every d in union(D(r), r in A(m)):
                 exact_current_version(d) AND unexpired(d)
                 AND applicable_task_and_source(d)
```

This is an engineering implementation of dependency invalidation and scoped competence evidence from the supplied Stack. It does not substitute a graph score for Hampton's Qi coordinates or claim to implement the manuscript MQ recurrence. Node count, link count and model confidence do not award capability or permission.

## How to inspect it

Open **More tools → Activity map**, select a node, and follow **Incoming links (backlinks)** or **Outgoing links**. The local graph focuses on the selected node and its immediate neighbors. Search and type filters apply to neighbors while the focus remains visible; All nodes exits local focus. Links use recorded direction and labels. They do not infer an association or call a model.

Document-task nodes disclose supplied and cited counts separately. Exact lesson-reference nodes survive withdrawal without reconstructing historical words. When an exact kept version remains in the displayed snapshot, a link leads to that retained lesson. These are bounded projections of existing records; native method checks remain responsible for actual availability. The map is not yet a complete semantic wiki.

## Reference ideas and where they fit

Karpathy's **LLM Wiki** proposes maintaining linked Markdown knowledge pages alongside original sources, with ingest, query and maintenance operations. It is an architecture note, not an empirical claim of correctness or guaranteed savings. [Karpathy, original gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Obsidian displays notes and explicit links as a graph and supports focused local graphs. Backlinks expose notes linking into the selected note; internal links can target notes or headings. These provide useful navigation patterns for ARCHi's attributable records. [Graph view](https://help.obsidian.md/plugins/graph), [Backlinks](https://help.obsidian.md/plugins/backlinks), [Internal links](https://help.obsidian.md/links).

Our adaptation keeps source records, generated interpretations, reviewed lessons, reusable methods and development outcomes distinct. A source can report a false claim; a wiki summary can misinterpret its source. Exact references establish lineage, while semantic support needs its own review.

| Layer | Existing owner | Remaining wiki work |
| --- | --- | --- |
| Selected original material | ReadingSourceLibrary and shared-document owner | Broader authorized source formats and stable cross-document citation anchors |
| Synthesized knowledge | Existing source-bound reading answers | Versioned draft/accepted claim and concept pages, editable Markdown export |
| Corrections and lessons | Kept lessons, source bindings, native memory dependencies | Dependency invalidation across typed semantic claims and contradictions |
| Reusable procedures | DocumentProcedureLibrary and reviewed task journal | Broader domains, measured transfer and skill certification |
| Graph and backlinks | CompanionGraph and DocumentWorkGraph projections | Source/concept/claim navigation and broken-reference maintenance across the future wiki |
| Reasoning and cost | Existing local Qwen routing and Token Steward | Bounded wiki synthesis requests with selected sources and measured cost; no background rebuild on navigation |

Next implementation should add versioned claim/concept pages to the existing memory owner, with exact source anchors and correction propagation, then let Qwen propose bounded updates for review. A shared SQLite or Markdown index may be a rebuildable view; it must not become a competing owner of companion identity, permissions or canonical outcomes. Obsidian interoperability can use ordinary Markdown links and explicit export/import review. No external vault, WikiOS database or second assistant was connected by this increment.

## Source and validation boundaries

The supplied `ARCHi_Master_Stack_R2.pdf` is retained privately with its SHA-256 and reading record in `docs/research/2026-09-25-stack-and-representation/local-sources.json`. L07 calls for source-addressed memory and dependency invalidation; L06 calls for scoped statistics, reusable methods and source-withdrawal recomputation. This increment implements that document-method path. The private manuscript remains an engineering source; no claim of patent validity, claim satisfaction, calibrated latent quotients or complete research installation follows.

Changed runtime: `DocumentWorkLearningContext`, `CompanionStore` method/review admission, `DocumentWorkGraph` and Activity map navigation. Focused fixtures use in-process deterministic clients. See the delivery ledger for build, installation, exact checks and publication evidence. No model training, live inference, ARC puzzle campaign or full test suite is required for this increment.
