# Knowledge particles, Liminal's body and AR

3 October 2026 · Native integration contract and platform gates

The memory map, Seed and Liminal body should present the same current records through the same particle bindings. A change of view changes their positions and visibility, not their identity, evidence or owner. ARCHi's native records remain canonical; WikiOS and other surfaces remain linked interfaces.

The installed native refinement is build **0.7.0 (1)**, binary UUID **B10CA7BD-C04B-38CF-BA9C-F17501255CD9**. The matching compiled/installed UUID, strict local signing and unchanged bytes for 23 monitored profile files are recorded in the [sanitized receipt](accountability/evidence/r03-particle-mechanic-refinement-2026-10-03.json). Native accessibility inspection confirmed exact source/version selection, retained selection when search excludes it, Reveal, then Focus → Gather → Unfold → Back with the same selected version. Focus displayed 4 of 25 records and 6 connections; Back restored 25 records and 60 connections. This is not full-size visual, sustained frame-rate, Unity or iPhone AR acceptance.

**The native graph-to-authored-body morph is implemented and has passed focused contracts and production Metal endpoint checks.** It is delivered as the later update recorded in the [morph receipt](accountability/evidence/r03-graph-beast-morph-2026-10-03.json); the earlier installation above remains a separate historical receipt. Unity and iPhone AR are not included in this native morph.

## Reuse these owners

| Responsibility | Existing implementation | Required connection |
| --- | --- | --- |
| Current records, source revisions and selection | `CompanionStore`, `CompanionGraphSnapshot`, existing inspectors | Resolve every selection against the current origin and graph digest. Preserve source/version/backlink inspection. |
| Native graph layout and common Seed particles | `CompanionParticleScene.swift`, `KnowledgeParticleField.swift`, `CompanionMemoryParticles.swift` | Reuse the record IDs and bounded force layout. Currently the field has orb and constellation endpoints. |
| Dense Liminal record/art correspondence | `LiminalKnowledgeBindings.swift`, `LiminalPointStructure.swift` | Reuse the central transient allocator and the full current graph. Each record owns one anchor and 32 authored art-particle IDs. Filtering must not reassign them. |
| Authored body motion and appearance | `LiminalPointAsset.swift`, `LiminalMetalView.swift`, `LiminalV008Runtime.swift` | Sample the qualified v008 asset. Retain original garnet Seed, personal colors, equipment, authored motion and reduced-motion behavior. |
| Unity Room and Arena | `UnityPresentationConnection.swift`, `LiminalParticleRenderer.cs`, `NativeEvolutionBridge.cs` | Preserve the native bindings while wrapping transport in the current Unity session. Add graph positions/morph support through a reviewed descriptor extension; current body rendering does not establish that extension exists. |
| Phone records and visuals | `ios/ARCHi/ARCHiStore.swift`, `HistoryGraph.swift`, `LivingFormView.swift`, `LiminalPortrait.swift` | Keep phone History as its existing owner. Replace the current portrait-plus-overlay implementation only after the point renderer qualifies. |

Native source files above are in `desktop/Sources/ARCHiDesktop/`; Unity runtime files are in `unity/ARCHi/Assets/ARCHi/Runtime/`. See [native authority](native-authority-and-lineage.md) and the authored workspace’s `ios/CANONICAL_LEDGER.md` for iPhone continuity.

## Graph → authored body

The presentation join is `origin + graph record ID + graph digest + asset manifest digest + art particle ID`. An art ID identifies a point in the authored package; it is not a second memory record. The allocator owns correspondence only, not memory or development. A cluster can contain many visible points while representing one record.

For a bound art particle, let `g` be its position around the record's graph anchor and `b` its sampled authored body position. The implemented native display interpolation is:

```text
s = u*u*(3 - 2*u),              0 <= u <= 1
p(s) = (1 - s) g + s b
```

This is an engineering presentation rule, not a Hampton theorem or a paper result. The current transition is straight and bounded between its endpoints, with a smooth start and finish. Reduced Motion selects the endpoint directly. Graph clusters use deterministic offsets capped at six screen points; the anchor stays exact. The original package's `nearest-half-up` sample clock remains authoritative for its body choreography; display interpolation must not silently redefine that source motion. The production Metal test confirms the Beast endpoint is byte-identical to the existing renderer’s inspection endpoint at the same 50,000-point detail level. This is a synthetic three-record rendering check, not a personal learning result.

Use one captured graph/asset/binding projection for draw, hit-test, snapshot and cache identity. Cache identity must include graph revision and current evidence support, not only layout. The overlay and selection positions follow successful GPU completion, rather than a potentially newer requested animation position. Authenticated target-frame bytes are reused across filter/focus/viewport changes. A selected record remains selected through search, focus and morph while it remains current. Hidden records can be revealed; removed or invalid records cannot remain actionable. Profile replacement, asset replacement or session change retires stale picks and render work. If a full activity graph omits a memory record because of its bounded capacity, the morph falls back to the ordinary map; it does not invent a binding. The two current graph projections may give one source-bound lesson different working-copy availability labels. Only that documented status difference is permitted; all version, source, text and evidence fields must still match.

Unbound source points may provide body density. They must not be counted as records or shown as selectable knowledge. The native morph currently uses the bounded 50,000-point prefix, which retains every mapped cluster; it does not claim an adaptive-detail performance qualification. A lower-detail render hides art points without dropping underlying records; omitted visual anchors must be disclosed and remain reachable through the inspector/list. Original body bytes and art IDs remain intact.

## Experience and expression

Retained information, a proposed method, its application and a reviewed outcome remain different records. Graphics can distinguish retained information from attributable reviewed experience using the existing `LiminalFormDevelopment` support projection. They cannot manufacture helpful applications by being replayed, viewed or animated.

Direct experience may strengthen an existing lesson only through its current application/outcome owner, exact source bindings and review. Duplicate, stale, corrected or withdrawn support must not retain growth credit. Derived or distilled information can remain useful and inspectable without claiming that the companion performed the underlying event. The relative developmental value of experience is an explicit product rule to measure; particle brightness does not establish scientific truth, measured capability, battle strength or permission.

## iPhone and AR gates

The current phone Living Form switches three endpoint images and draws 72 cosmetic points around up to 12 visible graph anchors. `LiminalPortrait.swift` applies a small visual breath to a PNG. There is no ARKit/RealityKit session in this target and no camera usage declaration in `Info.plist`; `FieldWalkView.swift` is Core Location/MapKit. These paths must not be described as a live point body or AR implementation.

The qualified local v2 package contains an 800,000-point master, a 200,000-point runtime set, and 120 frame files of 6,400,000 bytes each: **768,000,000 bytes of frame payload**, before other assets. Its current loader supports 50k/100k/200k subsets. Phone delivery needs a separately qualified deterministic subset/compression strategy with retained art IDs and receipts; simply copying endpoint PNGs or weakening hash checks is insufficient. The source coordinates are authored scene units, so world presentation also requires an explicit, checked conversion to meters and orientation.

Implement AR inside the existing native iPhone target after the shared projection and point renderer qualify:

1. Request camera access when entering the optional AR view. Gate on supported device/session configuration and provide a truthful non-AR fallback.
2. Let the user place the companion and explicitly choose a target. Keep target ID, world transform, timestamp, tracking status and AR session identity transient.
3. Animate the existing selected record cluster along a bounded arc toward that target. Placement/raycast success alone does not identify an object or establish a remembered observation.
4. Retire targets on tracking loss, session reset, backgrounding and profile/source invalidation. Do not reuse world transforms in a new session without requalification.
5. Route an explicitly kept observation through the existing record/source/outcome flow. Neither the camera nor a completed arc grants memory, experience or battle rewards.

Phone History and desktop records currently have separate owners and no automatic merge. Cross-device continuity requires an explicit versioned transfer with origin, revisions, source bindings, conflict handling and readback. A shared visual identity does not prove shared live memory. Physical-device camera/tracking, interruption, thermal and sustained frame-time acceptance remain required; simulator or desktop screenshots cannot close these gates.

## Research belongs at the mechanism it changes

The following primary abstracts were checked on 3 October 2026. This is research routing, not a reproduction or installation of the methods.

| Reference | Mechanism in the source | ARCHi use and gate |
| --- | --- | --- |
| [Mixture of Self-Improving Branches for Agent Harness Optimization](https://arxiv.org/abs/2609.37834v1), 29 September 2026 | Evolves harness branches, their development subsets and proposal policies; a router selects complementary branch heads before execution. | A candidate for evaluated method/harness selection. Keep development and held-out results separate, preserve exact executable versions and require promotion/rollback. A branching graph visualization does not implement MSIB. |
| [SAS: Simple Attention Sparsification via End-to-End Optimization of Context Ranking](https://arxiv.org/abs/2609.13141v1), 11 September 2026 | Trains continuous selector scores through log gates inside attention softmax; supplies a memory-efficient Triton implementation. | A model/backend training change requiring compatible kernels and evaluation. Graph filtering, node attraction and app context selection do not install sparse attention. |
| [Recursive Self-Improvement via On-Policy Distillation for Reasoning](https://arxiv.org/abs/2609.30652v1), 25 September 2026 | DCE updates the privileged teacher across rounds; SRCL trains on shorter verified self-rewrites. | A separate model-weight training workflow with verified targets, dataset/checkpoint provenance and held-out tests. Runtime memory growth and Q2E updates remain distinct. See the [existing learning intake](research/2026-09-29-memory-learning-selection/README.md). |

These mechanisms are relevant to Hampton's representation, memory, learning and adaptive computation programme. They do not establish equivalence with every Q2E equation, patent implementation, or a validated improvement in the installed app. The visual contract exposes current records and attributable changes; it does not supply those experiments.

## Focused completion evidence

Check stable record/art IDs and exact endpoints through graph → body → graph, filter/focus/reveal, profile switch and restart. Check missing assets, failed qualification, stale sessions, removal/correction and invalid support. Confirm rendered and selected positions agree throughout motion. Exercise reduced motion, hidden suspension and fallback explicitly. Measure active presentation against the 30 fps target with automatic detail reduction on the actual target devices. Keep physical iPhone/AR and Unity results separate from native macOS results. No model calls, puzzle runs or broad benchmark suite are required for these presentation gates.
