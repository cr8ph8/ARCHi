# Liminal point asset v2 — preserved v008 source clock

The filename is retained for existing links. Version 1 assumed linear subframe motion and never qualified a production asset. The licensed source run showed that the pinned transition controls use `smooth($F,24,60)` and `smooth($F,72,108)`: quarter frames hold the lower sample, while half/three-quarter frames hold the upper sample. Version 2 makes this measured nearest-half-up clock explicit; v1 packages are rejected. Motion tolerances are unchanged. The original HIP and VEX are unchanged.

This is the shared, source-bound contract for native Metal and Unity presentation. It does not create knowledge records or grant an evolution milestone. The exporter is an authoring tool for Houdini's `hython`; ordinary Python can validate the resulting package. The first licensed export correctly failed its v1 interpolation check. Qualification now requires the v2 clock comparison and separate renderer review.

The only accepted authoring scene is `Liminal-v008-lion-spin-blend.hiplc`, SHA-256 `2a56c4faf40a8920109df44e8bc2dad599b2b45b67a26bf2bc4fd0c93dd60cc1`. v002 exports are rejected. Output is a new directory, never an overwrite. A separate new working directory contains a source copy; the original scene and dependencies are read-only inputs. No scene is saved back and no render is launched.

## Loose package and binary layout

Install the qualified package as `Resources/LiminalV008` in the native app and `Assets/StreamingAssets/LiminalV008` for Unity. Consumers must use the manifest and digests; folder names do not establish qualification. All filenames below are relative to the package root. Links, absolute paths, `..`, duplicate JSON keys, nonfinite values and unexpected lengths are rejected. Maximum package size is 1 GiB; maximum manifest or comparison JSON size is 1 MiB each.

Every binary is headerless, little-endian. Float values are IEEE-754 binary32. UInt32 values are unsigned 32-bit integers. Vector components are XYZ or RGB in that order; no padding occurs.

| File | Record layout | Count and size |
| --- | --- | --- |
| `endpoints.bin` | `uint32 id`, then **standing**, **curled**, **orb**, each `{float3 P, float3 Cd, float radius, float emission}` | 800,000 records, stride 100; 80,000,000 bytes |
| `master-cohorts.bin` | `uint32 standingCohort, uint32 curledCohort` | 800,000 records, stride 8; 6,400,000 bytes |
| `lod-ids.bin` | `uint32 id` | 200,000 records, stride 4; 800,000 bytes |
| `frames/NNNN.bin` | `{float3 P, float3 Cd, float radius, float emission}` | 200,000 records, stride 32; 6,400,000 bytes per distinct sample |

Master records are in ascending original ID order, exactly 0 through 799,999. Cohort records use that same order and contain values 0 through 63. Runtime frame records use the order in `lod-ids.bin`; record position is never a graph identity. Source attributes `sourceP`, `curlP`, and `targetP` must match the master standing/curled/orb positions within the receipt tolerance before export is admitted.

The rank for ID i is SHA-256 of UTF-8 `archi-liminal-lod/v1\n` + the lowercase pinned HIP digest + `\n` + the base-10 ID with no leading zeros or final newline. Sort lexicographically by the 32 digest bytes, then integer ID. Retain the first 200,000 IDs. The first 50,000, 100,000 and 200,000 records form nested LODs. Every level uses actual sampled source motion; it does not regenerate an orb, noise, targets or colors.

There are manifest entries for all integer frames 1 through 120 at 24 fps. Endpoint frames are standing 24, curled 66 and orb 108. A frame's time in seconds is `(frame-1)/24`. The complete 120-frame clip occupies five seconds, including its last frame's display interval. Identical complete sample files may be stored once: later frame entries then refer to the earlier filename, hash and length. No approximation qualifies for deduplication. Runtime selects frame `floor(clamp(progress,0,1)*119+0.5)+1`, matching the source $F clock; hold the first/last sample outside the clip. It does not blend between two poses or generate intermediate states. Radius and emission remain nonnegative. Runtime reads only its chosen LOD prefix from the selected file and shares that buffer across both shader inputs. Display refresh may exceed the 24 Hz authored motion cadence; the separate 30 fps rendering target remains.

## Coordinate and appearance conventions

Positions are the actual local SOP `P` values from `/obj/LIMINAL_POINTFORM/PARTICLE_CHOREOGRAPHY`, before `EXPORT_ATTRIBUTES`. They use Houdini's right-handed XYZ basis, +Y up. They are **authored scene units, not a claim of metres**. The manifest retains the evaluated object-to-world row-major 4×4 matrix in Houdini row-vector convention; renderers use local coordinates for companion placement. Native Metal preserves XYZ. Unity reflects Z: `(x,y,z) → (x,y,-z)`; camera/orbit transforms must apply the same conversion. Both renderers apply their presentation fit/placement outside the asset and must not rewrite stored coordinates.

`Cd` is the actual exported linear Rec.709 RGB attribute, before the supplied OCIO display transform. `radius` is actual `pscale`, not diameter. `emission` is the actual nonnegative scalar `heat`; the common emissive color is `Cd * emission`, with tone mapping/bloom specified by the renderer, not baked display RGB. A matching final appearance still requires visual qualification. Export checks `width == 2*pscale`, finite fields, stable IDs, matching pose counts, 64 source/curled cohorts and source diagnostics.

## Exact manifest shape

`manifest.json` uses the following keys. Values represented below as `SHA256` are lowercase 64-character hexadecimal digests; actual files contain real values. A file reference always has exactly `file`, `sha256`, and `bytes`.

```json
{
  "schema": "archi-liminal-point-asset/v2",
  "assetID": "liminal-v008",
  "source": {
    "hipSHA256": "2a56c4faf40a8920109df44e8bc2dad599b2b45b67a26bf2bc4fd0c93dd60cc1",
    "houdiniVersion": "22.0.429",
    "node": "/obj/LIMINAL_POINTFORM/PARTICLE_CHOREOGRAPHY",
    "originalUnchanged": true,
    "dependencies": [{"file": "geo/relative-source-file", "sha256": "SHA256", "bytes": 1}]
  },
  "pointCount": 800000,
  "runtimePointCount": 200000,
  "encoding": {"byteOrder": "little", "float": "ieee754-binary32", "masterStride": 100, "cohortStride": 8, "idStride": 4, "sampleStride": 32},
  "coordinates": {
    "space": "houdini-sop-local", "handedness": "right", "upAxis": "+Y", "units": "authored-scene-units",
    "nativeMapping": [1, 1, 1], "unityMapping": [1, 1, -1],
    "objectToWorldRowMajor": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
  },
  "appearance": {"colorSpace": "linear-rec709", "radiusAttribute": "pscale", "emissionAttribute": "heat", "emissionRule": "Cd*heat"},
  "timeline": {"fps": 24, "firstFrame": 1, "lastFrame": 120, "interpolation": "nearest-half-up", "poseFrames": {"standing": 24, "curled": 66, "orb": 108}},
  "bounds": {"min": [-3, -3, -3], "max": [3, 3, 3], "maximumRadius": 0.01, "maximumEmission": 8},
  "master": {"file": "endpoints.bin", "sha256": "SHA256", "bytes": 80000000},
  "cohorts": {"file": "master-cohorts.bin", "sha256": "SHA256", "bytes": 6400000},
  "lod": {
    "algorithm": "sha256-rank-v1", "counts": [50000, 100000, 200000],
    "ids": {"file": "lod-ids.bin", "sha256": "SHA256", "bytes": 800000}
  },
  "frames": [{"frame": 1, "file": "frames/0001.bin", "sha256": "SHA256", "bytes": 6400000}],
  "motionControls": {
    "point_count": 800000, "size_gain": 0.4, "glow_gain": 1, "curl_frequency": 2.1,
    "release_stagger": 0.045, "lid_opening": 1.15, "lid_definition": 0.8,
    "local_spin_turns": 1.15, "local_spin_radius": 0.065, "micro_curl_amount": 0.01,
    "lion_initial_spin": 35, "lion_spin_max_offset": 0.3
  },
  "endpointImages": {"status": "unavailable", "camera": null, "images": [], "reason": "No camera-qualified transparent endpoint renders were produced."},
  "comparison": {"file": "comparison.json", "sha256": "SHA256", "bytes": 1}
}
```

The example shortens `frames` to one entry; a valid package requires all 120 entries. Bounds and maximum appearance values are measured across the full master and every exported sample. The source's object transform and version are measured, not copied from the example. Dependency records describe authoring inputs; those inputs are not installed runtime files. The pinned source's exact required control names, parameter values, input paths and diagnostics are checked, never silently substituted.

Without `--render-endpoints`, `endpointImages` has the unavailable shape above. With that option it is `{status: "qualified", renderer: "archi-point-reference/v1", camera: {projection: "orthographic", center: [x,y,z], span: number, direction: [0,0,-1], up: [0,1,0]}, images: [{pose: "standing", frame: 24, file: "images/standing.png", sha256: "…", bytes: number}, …], receipt: {file: "endpoint-images.json", sha256: "…", bytes: number}}`. There are exactly three images, ordered standing, curled, orb at frames 24, 66, 108. They are deterministic transparent 512×512 RGBA PNG point-reference renders from actual endpoint LOD records, explicitly **not Karma beauty renders**. The reference producer uses additive linear `Cd * heat` Gaussian discs, radii at least half a pixel, exponential tone mapping and sRGB encoding, with straight alpha; this is a declared reference appearance, not final photorealistic acceptance.

The fixed whole-clip camera looks from +Z toward −Z, with +X right and +Y up: center is `(bounds.min + bounds.max)/2`; span is `max(max[k]-min[k]+2*maximumRadius for k in XYZ)*1.12`. The square viewport uses that vertical/horizontal span. Native preserves this basis; Unity reflects both points and camera Z. The `archi-liminal-endpoint-images/v1` receipt binds the source digest, node, master digest, camera, renderer, resolution `[512,512]`, `transparent: true`, and each image to its sampled-frame digest. It binds immutable content rather than the manifest's digest, avoiding a digest cycle. The validator reproduces camera and PNG pixels from binary samples. No v002 image or supplied preview can qualify.

## Comparison receipt and admission

`comparison.json` contains `schema: archi-liminal-motion-comparison/v2`, `status: passed`, the pinned `hipSHA256`, the qualified `node`, `sourceCooked: true`, `sampleFrames: [1..120]`, `runtimePointCount: 200000`, `endpointFrames: [24,66,108]`, `checks`, `interpolation`, and `limits`.

`checks` records maxima for `identityError`, `pathLimitError`, `endpointPoseError`, `poseAttributeError`, `widthError`, and integer `idMismatchCount`. ID mismatches must be zero; diagnostic/pose/width errors must not exceed 0.00001 authored units. All attributes are finite, radius/emission nonnegative, source/curled ID order identical at every sampled frame, and both cohort values in 0...63. Each exported endpoint LOD record must also match its corresponding full-master record exactly after binary32 packing.

`interpolation` contains `evaluated: true`, `subframes`, `comparedPointCount: 200000`, and maximum errors `position`, `color`, `radius`, `emission`. The 42 subframes are each base in `[24,30,36,42,48,54,59,72,78,84,90,96,102,107]` plus `.25`, `.5`, `.75`, in that order. The exporter reads frozen geometry at each explicit frame, then compares all 200,000 IDs to the lower integer sample for `.25` and the upper integer sample for `.5` / `.75`. Position error is Euclidean distance; color is maximum absolute component error; radius/emission are absolute error. The exact source expressions and their HScript language are pinned as well as VEX, inputs and parameters.

`limits` is exactly `{"position":0.01,"color":0.01,"radius":0.00001,"emission":0.05}`. All comparison keys described above are required; unknown keys are rejected.

Admission limits are position ≤0.01 authored units, color ≤0.01 linear RGB, radius ≤0.00001 authored units and emission ≤0.05. These are explicit initial tolerances, not measured success. A failure retains diagnostics without writing a qualified manifest. Changing tolerances requires a reviewed contract change. Endpoint renders, unsampled subframe equivalence, native/Unity display equivalence, performance and owner visual acceptance remain separate qualifications.

The validator verifies structural bounds, every file hash/length, binary values, rank and IDs, nested LOD correspondence, endpoint/master correspondence and receipt completeness. A receipt is source evidence, not cryptographic proof that Houdini ran; validation cannot turn a fabricated or unexecuted receipt into a trusted authoring run. Only a passing source run may create a package manifest. Native/Unity review and installed acceptance remain additional gates.

## Authoring command and bounded operation

Keep the two Python files together. Use an installed, licensed Houdini `hython` with the compatible SOP definitions (the source was authored with Houdini 22.0.429). Run once with two nonexistent, separate output directories outside the preserved Liminal tree:

```sh
"/path/to/hython" script/liminal_v008_export.py \
  --source "/path/to/Liminal/hip/Liminal-v008-lion-spin-blend.hiplc" \
  --output "/path/to/new/LiminalV008" \
  --work-directory "/path/to/new/LiminalV008-authoring" \
  --render-endpoints
python3 script/liminal_v008_validate.py "/path/to/new/LiminalV008"
```

The exporter pins and copies the HIP and four actual FBX/PNG dependencies, preserving the inspected `$HIP/../geo/...` paths. It rejects scene/VEX changes, missing parameters, unexpected source connections, changed object transforms, count/ID/cohort differences, nonfinite fields, cook errors and warnings. It does not substitute another scene, change motion parameters, run a ROP, or save the scene. Source and dependency hashes are rechecked after cooking. The exporter requires the Indie license category before copying, after loading and before writing a successful receipt. A failed run retains those checks and per-subframe diagnostics in its authoring directory. No Houdini installation is downloaded or licensed by this tool.

Geometry extraction uses `geometryAtFrame(frame)` frozen geometry and HOM bulk binary attribute buffers. One cook and fixed-size array buffers are retained, with full endpoint rows streamed through 4,096-record chunks. The tool never creates 800,000 Python `hou.Point` objects or holds the complete clip in memory. It retains three pose-vector buffers and at most a few sampled-frame buffers; Houdini's internal scene/cook cache is separate from this exporter memory bound. A worst-case package without deduplication has 855,200,000 binary bytes, plus bounded JSON and three small PNGs, below 1 GiB. Source copies and endpoint scratch buffers live only in the separate authoring directory and are not part of the runtime package.

`manifest.json` is written only after source and interpolation checks, then independently validated. Any later validation failure revokes that newly written manifest and writes `export-failure.json` in the authoring directory; interpolation failures also retain `comparison-failed.json`. Successful authoring writes `export-receipt.json` there, explicitly leaving runtime display qualification and owner visual acceptance false. The exporter never creates the separate product `qualification.json` or claims installed-app acceptance.

The focused synthetic tests are `python3 -B scripts/tests/test_liminal_v008_format.py`. They check packing/ranking, incomplete or unexecuted receipt rejection, motion error detection, traversal/link/duplicate-key rejection, source pin rejection, file corruption, incorrect endpoint joins and image/sample binding. Synthetic fixtures are not v008 source-cook evidence.

Implementation follows SideFX's [bulk geometry attribute API](https://www.sidefx.com/docs/houdini/hom/hou/Geometry.html), [SOP cooking API](https://www.sidefx.com/docs/houdini/hom/hou/SopNode.html), and [HIP loading API](https://www.sidefx.com/docs/houdini/hom/hou/hipFile.html). The source clock decision follows the actual v008 probe and SideFX’s [time variable reference](https://www.sidefx.com/docs/houdini/network/expressions.html) and [explicit frame geometry API](https://www.sidefx.com/docs/houdini/hom/hou/SopNode.html).
