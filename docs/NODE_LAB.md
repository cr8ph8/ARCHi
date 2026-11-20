# Native Node Lab

Node Lab displays the existing desktop companion, shared source, kept lessons, temporary context and assistant receipts as a native graph. Open it from the workspace sidebar, Window menu or receipt details. Constellation, Radial and Flow are alternate layouts of the same records; search, type filters, zoom and a selectable list support inspection.

Selecting a node shows its recorded status and available source details. Open the existing Assistant, Work together, Memory or local receipts screen through the inspector. The footer exposes the existing assistant activity and Stop control while work is running.

The graph is derived on demand from CompanionStore. Reading and filtering it make no model call and create no graph database. Request-local reference labels are scoped by provider, request and captured input/context. Repeated labels in Compare do not become one global identity. Historical records do not restore withdrawn lesson words or reuse a temporary record's changed content. Private Qwen context is excluded from external-lane projections.

The projection caps displayed nodes/edges and reports truncation. A periodic presentation refresh checks expiry; it does not infer new relationships. Layout, proximity, citations and graph size do not establish truth, importance, learning or permission. Placement, identity, appearance, evolution, persistence and routing remain in their existing owners.

Source: [projection](../desktop/Sources/ARCHiDesktop/CompanionGraph.swift), [view](../desktop/Sources/ARCHiDesktop/CompanionGraphView.swift), [store integration](../desktop/Sources/ARCHiDesktop/CompanionGraphWorkspace.swift). Included domain, controlled store and native presentation tests cover source/lesson freshness, provider separation, stopped callbacks, bounded geometry and navigation. Their inclusion does not qualify this export; see [validation](ALPHA_VALIDATION.md).

Node Lab is inspection and navigation. It does not execute arbitrary drawn edges, infer social relationships, import a whole vault or create an agent swarm. Full keyboard traversal, VoiceOver use and representative larger-record usefulness remain qualification work.

## Seed Dive

Right-click the floating companion and choose **Dive into Seed**, use the same button on KIN’s card, or open **Seed Dive** in the sidebar. The particle shell opens onto the current Node Lab projection. Select a dot or use the searchable **Records** list. The inspector gives each connection its recorded direction and label. Follow a link to see the other record, including links outside the selected layer. **Seed surface** returns to the shell.

Core contains the companion. Sources contains source references. Memory contains kept lessons and temporary context, with retention shown on the individual record. Activity contains requests and model calls. Outcomes contains answers and omissions. Layer totals count projected records, and the map counts links with both endpoints visible. The shell’s decorative particles carry no record identity. The map’s layout encodes record type.

The bundled WebKit view receives the current bounded snapshot as structured data. It uses a nonpersistent store and has no script bridge back to ARCHi. Opening the inspector or following a link has no Keep, Apply or evolution action. Native Node Lab remains available from the inspector footer. Quiet mode and reduced motion skip the entry animation. On a Mac, run the focused host test with `swift test --package-path desktop --filter SeedDiveTests`.
