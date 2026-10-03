# Liminal v008 rendering techniques — 27 September 2026

Outcome: use the existing authored motion as sampled data, render it on the GPU,
and keep knowledge identity independent of display density. This review informs
the implementation; it is not evidence that v008 has passed native/Unity visual
or performance acceptance. No third-party repository code or example assets have
been imported by this review.

| Primary source | Useful technique | Decision for ARCHi |
|---|---|---|
| [SideFX HOM Geometry](https://www.sidefx.com/docs/houdini/hom/hou/Geometry) | Bulk binary attribute access avoids per-point Python object calls. | Read P, Cd, pscale, emission and IDs in bulk during export. Check correspondence before attributes are stripped. |
| [SideFX Labs VAT 3](https://www.sidefx.com/docs/houdini/nodes/out/labs--vertex_animation_textures-3.0.html) | Bake complex authored animation for GPU playback; explicit engine coordinates and scale. The documentation identifies texture-memory and interaction limits. | Apply the bake-and-play principle with independently hashed binary frame buffers and stable IDs. Keep full precision initially; measure before introducing lossy compression. |
| [keijiro/Pcx](https://github.com/keijiro/Pcx) and [renderer source](https://github.com/keijiro/Pcx/blob/master/Packages/jp.keijiro.pcx/Runtime/PointCloudRenderer.cs) | Point-cloud storage separate from GPU presentation; mesh, buffer and texture approaches. Repository code is Unlicense; example models have separate CC BY attribution. | Use GPU buffers, not an object per particle. Do not import sample models. Its disk geometry-shader route is unsuitable for this Metal target. |
| [Unity Metal compatibility](https://docs.unity.cn/Manual/metal-requirements-and-compatibility.html) and [shader targets](https://docs.unity3d.com/6000.0/Documentation/Manual/SL-ShaderCompileTargets.html) | Metal does not provide Unity geometry-shader support. | Expand camera-facing triangles in the vertex shader using vertex IDs. Preserve the existing render pipeline. |
| [Unity RenderPrimitives](https://docs.unity.cn/Documentation/ScriptReference/Graphics.RenderPrimitives.html) | Procedural GPU-buffer rendering with custom shaders. | One renderer and shared buffers for the room and Arena; verify the installed Unity API before use. |
| [Apple point-cloud sample](https://developer.apple.com/documentation/ARKit/displaying-a-point-cloud-using-scene-depth) and [Metal samples](https://developer.apple.com/metal/sample-code/) | GPU point positioning, explicit pipeline resources, and CPU/GPU synchronization. | Native Metal rendering and explicit image output. The ARKit capture portion is unrelated and is not added. |
| [Apple point primitive](https://developer.apple.com/documentation/metal/mtlprimitivetype/point) | Point primitives require an explicit point size. | Prefer quads for consistent native/Unity footprint; keep radius in the shared data contract. |
| [Graphology design choices](https://graphology.github.io/design-choices.html) | Stable explicit node and edge keys; iteration position is not identity. Graphology is MIT licensed. | Keep ARCHi's existing graph IDs and exact source/version inspector. Filter existing bindings rather than rebuild them from visible order. No JavaScript graph dependency is needed. |

Additional candidates reviewed: [SplatVFX](https://github.com/keijiro/SplatVFX),
[Unity VFX samples](https://github.com/Unity-Technologies/VisualEffectGraph-Samples),
[SideFX Labs](https://github.com/sideeffects/SideFXLabs), and
[GaussianSplats3D](https://github.com/mkkellogg/GaussianSplats3D) ([MIT license](https://github.com/mkkellogg/GaussianSplats3D/blob/main/LICENSE)).
These are useful references, but v008 is an authored particle sequence, not a
trained Gaussian scene. Adding Gaussian reconstruction, HDRP or another graph
runtime would expand this delivery without preserving the existing motion more
faithfully. Reconsider only against a measured limitation. Review the license of
the exact file/revision before any future code reuse.

## Shared quality decisions

- Preserve the 800,000-point endpoint master. Derive nested 50k/100k/200k subsets
  from immutable IDs; density changes never mint or reorder knowledge records.
- Use the same nearest-half-up sample on both GPUs, matching the measured v008
  `$F` clock. Version 1’s linear assumption failed the real source comparison.
  Check quarter/half/three-quarter frames without changing error tolerances.
  Do not regenerate curl noise independently in two languages.
- Use linear color data, bounded radiance and premultiplied transparent output.
  Compare the actual garnet/gold endpoints over both light and dark backgrounds.
- Load/authenticate frames off the UI thread. Bound the cache; stop hidden
  rendering. Reduce detail after sustained frame-budget misses, not every frame.
- Keep explicit endpoint images for fallback and snapshots. A SwiftUI snapshot
  of a Metal view is not a valid substitute for explicit capture.
- Keep source correction, removal and stale-session handling in the native
  knowledge owner. Art movement grants neither evidence nor authority.

## Qualification still required

The actual source-machine cook, endpoint images, motion-comparison receipt,
native/Unity visual comparison and installed 30 fps walkthrough remain required.
Documentation and source compatibility do not establish any of those results.
