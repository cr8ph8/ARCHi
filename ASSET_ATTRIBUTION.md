# Source and runtime artwork

ARCHi and QiMon are developed by Patrick “pH” Hampton. The included project-authored source, documentation, vector icons, application branding and runtime companion artwork are distributed under the repository's [MIT license](LICENSE). Third-party packages retain their own licenses.

The native resources include the existing Pearl/Lumen studies, teal companion forms, KIN Core Seed and First Light PNGs, and Quotient application icons/marks. Native SwiftUI renderers supply the additional procedural appearances and item cues. The Unity project reuses the same selected KIN/Quotient artwork and retains Pearl/Lumen authoring-reference scenes. This source update includes the runtime files needed by those source projects. Editable Blender/design projects and machine-specific authoring records remain outside the distribution.

The Broken Relay rules originated in Hampton's existing work and are retained in TypeScript and the separate Unity practice domain. See the [integration provenance note](docs/siggraph-local-companion-integration.md). Unity's [source provenance](unity/ARCHi/source-provenance.json) identifies the copied pilot and optional embedded tooling; its historical input hashes are distinct from current public-export hashes.

Eight runtime PNG copies had a Blender File text chunk removed for publication: Pearl, Lumen, KIN Seed and First Light in native and Unity locations. Only that metadata chunk is removed. Compressed image payload, decompressed scanlines and all other PNG chunks remain byte-identical to the development inputs. Runtime hash pins, asset contracts and Unity KIN provenance identify the sanitized exported bytes. This changes no image pixels and leaves the original authored files intact.

MIT reuse permission is separate from a claim that Hampton authored or authenticated a derivative. The proposed Hampton Designed seal describes explicit creator endorsement and balanced game specialties; copying a seal or creating a UID does not establish that provenance. The [policy](docs/HAMPTON_DESIGNED.md) adds no restrictions to MIT permissions.

Coplay's optional Unity Editor bridge is included under its own MIT notice. Unity engine/editor packages are declared dependencies with their own terms, not project-authored MIT artwork or code. No Unity/Blender installation, model weights, paid Reactor runtime, credentials or user records are bundled. See [third-party notices](THIRD_PARTY_NOTICES.md).

The nine WAV files under `Resources/QwenVoice/Samples` were generated on Apple silicon with the preset speakers of [Qwen3-TTS CustomVoice](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit). The accompanying `auditions.json` records the checkpoint revision, spoken line, performance direction, seed, file hashes, timings and originating Mac run.
