# Character sheets and runtime animation handoff

This is an authoring brief, not a runtime import manifest. Original references and their private provenance remain in the authored workspace. No reference attachment or runtime sprite package is published by this brief.

## Source and identity requirements

Keep original art, reviewed character design and qualified runtime assets distinct. A labeled pose sheet may guide silhouette and motion, but baked backgrounds, inconsistent crops or frame spacing prevent direct use as an animation atlas. Authored themes do not establish measured traits or routing permissions. Each character must retain its own identity and asset provenance.

Liminal's original garnet constellation Seed with a white pearl remains the cursor/interaction form of the same individual. A cub pose does not silently replace that Seed, the developed body or v008's qualified point asset. Their current owners and fallbacks remain intact.

## Produce two deliverables from one character source

**Design sheet:** front/side/back views, size comparison, stable core location, palette, expressions and motion notes. Include labels here. Declare whether each view is original reference, authored interpretation or a reviewed export.

**Animation package:** clean transparent RGBA frames without text or baked checkerboard, plus a small descriptor for character/form identity, source revision, atlas/frame hashes, frame rectangles, per-frame durations, pivot, logical size, scale variants, loop policy and static fallback. This descriptor is a proposed extension to the existing visual-asset pipeline; there is no current generic sprite importer to load it.

Start with separately inspectable square frames at one consistent authoring size, provisionally 512 × 512. Pack only after checking total texture/memory cost for each target. Frame count should serve the motion, rather than copying the labeled sheet's grid. Preserve edge padding for glow and sampling; use a stable pivot and logical bounds to prevent jumping. Record coordinate origin, row order, color space and alpha treatment explicitly for native and Unity consumers.

Prefer re-authoring the reviewed poses against a clean source. Cropping a flattened JPEG cannot restore missing alpha, occluded detail or consistent geometry. Keep the original as evidence; any regenerated frames remain visual candidates until inspected. Houdini v008 motion data continues through its point renderer and is not replaced by hand-invented sprite poses.

## Bind expression to existing activity

`KinLightRules.resolve` already maps observed activity to `KinLightExpression`; `CompanionPresenceArt` owns composition. Reuse those signals for any qualified animation, with a shared timeline and descriptor for the same individual.

| Existing signal | Proposed visual cue | Meaning limit |
|---|---|---|
| Rest/Quiet/hidden | Neutral still frame or minimal idle; suspend hidden playback | No inferred personality or learning |
| Working/orbit | Attentive pose with restrained orbit | Work is in progress, not necessarily productive |
| Fresh focus | Stable look/focus toward the selected passage | User-directed focus, not eye tracking |
| Responding/pulse | Bounded pulse while text arrives | Response activity, not verified truth |
| Ready/delight | Small opening gesture, then settle | Reply ready, not approved, correct or Helpful |
| Failed/hold | Still amber cue and accessible status | Task failure, not physical pain or damage |

Attack, hurt and locomotion frames belong to actual play events from the existing Arena owner. They must not trigger from chat sentiment, a failed answer or model-supplied commands. Generated animation never changes health, permissions, memory, measured capability or evolution.

## Focused qualification before activation

Check exact frame hashes and manifest bounds; alpha edges, consistent pivot, silhouette and readable scale on light/dark backgrounds; loop seam and duration; frame-time and memory at the chosen detail. Freeze to a meaningful frame for Reduce Motion and pause when hidden. Missing or invalid frames return to the existing qualified visual.

Use one digest-bound presentation identity across desktop, document focus, Companion room/Arena and later iPhone. Recheck session and appearance revision on async frame results. Existing native/Unity acknowledgments must identify what actually rendered; a sent descriptor is not render proof. Preserve equipment, personal palette, source-record selection and Seed continuity.

The first deliverable is one qualified Liminal idle/focus/ready set with explicit snapshots. A full combat library, seven new agents and automatic evolutionary forms are outside that first increment. No new artwork was generated or activated during this review.
