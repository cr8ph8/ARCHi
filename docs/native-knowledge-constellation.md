# Knowledge as a particle constellation

## 3 October 2026 — one native Seed and memory projection

The native companion and Memory map now consume `CompanionParticleScene`, a disposable projection of the current profile's bounded memory graph. `KnowledgeParticleView` draws both compact Seed and expanded-map anchors using the same graph-record IDs, positions, type colors and reviewed-support motifs. **Gather into Seed / Unfold memory** changes presentation; the selected record and inspector remain available. My companion's Memory & experience card opens the exact current record from its Seed lights. Returning from the map can highlight that record in the native Seed.

The existing native records remain authoritative. Sources, saved methods, exact versions and directed relationships remain in the graph even when they are not retained learning or have no reviewed application. Content deduplication is only optional reinforcement metadata: it never replaces or merges graph records. Multiple records referring to the same content do not multiply earned experience. A profile, version or source change invalidates an old pick and cached image. Original art, equipment, personal colors and saved milestones are preserved.

The compact camera keeps the authored Seed center fixed, including with only one memory. New memories do not relocate existing Seed anchors. Expanded layout remains a bounded presentation over recorded edges. Filtering hides records without recomputing their field. Reviewed-use satellites are finite art motifs, not additional memories, automatic truth, battle power or capability measurements. Imported/distilled knowledge can acquire stronger support through an attributable reviewed experience; visual density alone never grants that support.

PNG exports, hosted companion images and Reactor reference caches consume the same graph-and-support digest. Reduced Motion uses a directly renderable static Canvas. Hidden or inactive particle animation pauses. The projection is transient, contains no new saved ledger, performs no model calls and makes no source/learning writes.

**3 October refinement — shared anchors and navigation:** One native-owned disposable allocator now binds the qualified Liminal body, its inspector, PNG/Reactor exports and Unity handoff. A growth motif uses an existing selectable record anchor instead of independently hashing its content to another location. Each deduplicated content group chooses one current eligible record alias; every graph record stays inspectable. Corrections invalidate old picks and support. Removed anchors remain reserved during the owner/asset session. Fresh equivalent graphs reproduce initial positions after restart; retired reservation history itself is not persisted. Transport sessions retain independent replay checks while wrapping the same art IDs.

The map has one transient selection owner. Gather/Unfold and Back retain selected records and navigation context. Filtering leaves the inspector open with **Reveal selected record**. A missing exact version is retired, not replaced with a guessed newer version. Profile restore/recovery clears navigation and disposes the old particle allocation session. These changes add no profile migration, experience award or saved store.

The dense builder checks exact current graph/asset/owner bindings, unique disjoint qualified clusters and available source support. Capacity exhaustion leaves the original body visible with no invented motif. The existing Unity v1 structure wire remains compatible; unchanged geometry and asset hashes do not require a new helper just for anchor allocation. See the [refinement receipt](accountability/evidence/r03-particle-mechanic-refinement-2026-10-03.json) for delivered checks and their limits.

**Integration boundary:** native compact Seed/map drawing and qualified v008 growth now share record identity with their inspectors and exports. The 2D graph coordinates and authored 3D coordinates remain different representations of those records. A continuous 3D body-to-map transition, Unity Proto/KIN's ID-aware particle consumer, iPhone delivery, and installed cross-runtime frame-rate acceptance remain unfinished. User-reviewed helpful applications remain distinct from independent direct-experience verification and measured capability.

The sections below preserve the original 27 September map implementation and authoring boundary. Later v008 installation receipts supersede their historical statement that native point rendering was still absent.

ARCHi's existing **Activity map → Particles** draws one selectable light particle per record in its bounded graph snapshot. The same inspector, search, record-type filter, incoming links/backlinks, outgoing links and local-neighbourhood focus remain available. The accessible List view is retained. The companion's selected Seed color tints the central record; record types retain their own colors.

The **Orb → Connections** slider gathers or spreads that same set of IDs. Hover or select a particle to highlight its actual recorded links. Slow pulse is presentation only and can be switched off. App Reduce Motion and system Reduce Motion suppress pulse and curved travel. No background model calls, memory writes, growth updates or simulation jobs are caused by browsing.

## Source and design boundary

The supplied Liminal v008 Houdini study uses a deterministic standing-lion → curled-lion → orb choreography with stable particle IDs, 64 color/spatial groups, bounded local spins and a restrained initial sweep. Its retained 15-frame receipt describes 800,000 particles and a GPU flipbook; it is not a fresh native-app or Karma qualification. The delivery manifest and runtime exports describe an older version. The originals are preserved outside ARCHi.

This native implementation adapts the bounded local-motion principle. It does not load the 800,000-point scene, import its lion mesh, run Houdini inside ARCHi, or claim that art particles are memories. A record's ID is independent of `ptnum`, position, color, pulse and source-file ordering. Changes in source revision or provenance remain separate graph identities. Unlinked retained sources now appear, and declared parent links point to the exact version, including an unavailable-version marker after correction.

The supplied design discussion provided the integrated Memory/YAH navigation direction. Its Windows/Obsidian/SEAi installation claims are historical chat claims, not evidence of installed Mac capabilities. The source link and local-file audit remain in the private project evidence. No vault was discovered, scanned or synchronized by this increment.

Obsidian's [graph interaction](https://obsidian.md/help/plugins/graph) supplies the familiar node/link, hover, selection and filtering pattern. ARCHi's edges come from its existing records. Screen distance and visual clustering do not create semantic relationships or establish truth.

## Native motion

For graph record i, let a_i be its compact orb position and b_i its expanded position. For slider value t in [0,1], the renderer computes

    x_i(t) = (1-t) a_i + t b_i + d_i(t)
    ||d_i(t)|| <= min(0.065, 0.16 ||b_i-a_i||) sin(pi t)^1.5.

The native deviation uses a deterministic phase and 1.15 local turns. It is exactly zero at each endpoint; Reduce Motion sets it to zero everywhere. Units are normalized presentation coordinates, not metres, energy, confidence or quotient values. This is a bounded 2D adaptation, not a port of Houdini's 3D curl-noise field. A finite 36-step layout combines spacing repulsion, weak attraction along recorded edges and type anchors, clipping each increment and final radius. Motion never feeds back into the knowledge store.

Hampton's contribution here is the integration boundary: retained state, exact provenance, observable relationships and embodiment share record identity. The graph makes these inspectable; it does not demonstrate the efficacy of the broader Q2E equations.

## Export to Houdini

**Export for Houdini…** writes the full bounded snapshot as `archi-knowledge-particles/v1` JSON (up to 220 nodes / 500 edges). It includes string node IDs, types, orb/constellation positions and directed recorded relationships. It excludes titles, document bodies, prompts, attribution and local file paths. IDs and relationship structure still describe local records; export is explicit and local.

Use `script/houdini_knowledge_particles.py` in a new, unconnected Python SOP with a file-path parameter named `archi_map`. The adapter validates schema, size, finite positions, unique IDs and edge endpoints before creating geometry. It stores `archi_node_id`, `archi_kind`, `orbP` and `constellationP` on points and edge identity/relationship on open polylines. It follows the [SideFX Python SOP interface](https://www.sidefx.com/docs/houdini/hom/pythonsop.html). Validation from ordinary Python is supported; actual Houdini cooking is a separate check.

For dense Liminal embodiment, keep a separate table `art_particle_id → archi_node_id` and preserve the string ID through sampling/reordering. Multiple art particles may represent one record; never infer additional records from their count. Export pose correspondence before Liminal's `EXPORT_ATTRIBUTES` strip node, which removes pose/identity diagnostic attributes. A current v008 point export, stable binding table, native GPU renderer and cross-surface acceptance are still required before replacing the installed companion body. No write-back of animated coordinates into authoritative knowledge is implemented.

### Same authored particles: native graph-to-Beast projection

The later 3 October update adds **Form Liminal / Return to map** directly to the native Memory map. Existing graph clusters move into their fixed, authenticated v008 Beast coordinates. This read-only preview preserves the saved companion appearance. The 50,000-point surface retains every bound cluster; unbound points supply body artwork. Selection and overlays follow the last successfully rendered GPU progress. See the [implementation and AR gates](knowledge-particle-body-and-ar.md) and [separate delivery receipt](accountability/evidence/r03-graph-beast-morph-2026-10-03.json). Unity and iPhone AR remain separate integration gates.
