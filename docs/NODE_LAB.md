# Native Node Lab

Node Lab displays the existing desktop companion, shared source, kept lessons, temporary context and assistant receipts as a native graph. Open it from the workspace sidebar, Window menu or receipt details. Constellation, Radial and Flow are alternate layouts of the same records; search, type filters, zoom and a selectable list support inspection.

Selecting a node shows its recorded status and available source details. Open the existing Assistant, Work together, Memory or local receipts screen through the inspector. The footer exposes the existing assistant activity and Stop control while work is running.

The graph is derived on demand from CompanionStore. Reading and filtering it make no model call and create no graph database. Request-local reference labels are scoped by provider, request and captured input/context. Repeated labels in Compare do not become one global identity. Historical records do not restore withdrawn lesson words or reuse a temporary record's changed content. Private Qwen context is excluded from external-lane projections.

The projection caps displayed nodes/edges and reports truncation. A periodic presentation refresh checks expiry; it does not infer new relationships. Layout, proximity, citations and graph size do not establish truth, importance, learning or permission. Placement, identity, appearance, evolution, persistence and routing remain in their existing owners.

Source: [projection](../desktop/Sources/ARCHiDesktop/CompanionGraph.swift), [view](../desktop/Sources/ARCHiDesktop/CompanionGraphView.swift), [store integration](../desktop/Sources/ARCHiDesktop/CompanionGraphWorkspace.swift). Included domain, controlled store and native presentation tests cover source/lesson freshness, provider separation, stopped callbacks, bounded geometry and navigation. Their inclusion does not qualify this export; see [validation](ALPHA_VALIDATION.md).

Node Lab is inspection and navigation. It does not execute arbitrary drawn edges, infer social relationships, import a whole vault or create an agent swarm. Full keyboard traversal, VoiceOver use and representative larger-record usefulness remain qualification work.

## Following evidence

Enter a query and enable **Follow links** to see up to six records. ARCHi ranks exact word matches by their rarity in the current filtered snapshot. It reserves three places for direct matches, follows recorded edges one hop, then fills available places from the remaining matches. Select a linked result to inspect the source, relationship, and destination. Turning the option off restores the existing substring search.

The comparison uses seven synthetic release questions, including a stale native pass, contradictory receipts, a skipped native run alongside a portable pass, an error, and missing evidence. The synthetic comparison uses a 4,096-token context window for each arm. The hosted Mac preloads Qwen before timing the trials. Each question runs against full records, keyword results, and linked results. The two compact modes share a six-record budget. Both the app and the benchmark call the same retrieval function.

On a Mac with a supported local Qwen model already installed in Ollama, run:

    ARCHI_RETRIEVAL_MODEL=qwen3:8b ARCHI_RETRIEVAL_REPORT="$TMPDIR/archi-retrieval.json" \
      swift test --package-path desktop --filter GraphRetrieval

The report records the model digest, selected records, exact citation and verdict scores, measured prompt/output tokens, and retrieval-through-answer latency. ERROR identifies an unsuccessful trial. Absent token counts mean unavailable accounting. A wrong verdict or citation remains visible as a failed trial. These questions exercise source selection in a small controlled corpus. Production recall and speed require a separate workload.

Each trial also records a deterministic receipt readback. It uses the synthetic register to check that the selected release and every matching native receipt are visible. A missing receipt or truncated register withholds qualification. An empty set, a skipped run, or an error yields UNVERIFIED. Disagreeing pass/fail receipts yield CONFLICT. The full-register check is outside the model timing. The two verdicts stay visible side by side. This checker applies to the synthetic build schema and gives ordinary Node Lab records no qualification authority.
