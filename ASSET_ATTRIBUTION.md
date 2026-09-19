# Asset attribution draft for the unified source update

This is a proposed update to the prior public ARCHi attribution, carried forward from commit `ffee7ea9e77632de7cb13d816bff85dc498d9c1a` of the local publication checkout. The prior file states that the included project-authored source, documentation, vector icons, branding and selected runtime artwork are distributed under MIT. That existing statement is evidence for its published scope; it does not establish redistribution authority for every newer file in the development workspace.

Existing Pearl/Lumen, teal companion, KIN Seed/First Light, Quotient branding and PWA icon paths are inventoried in the release packet. Native and Unity copies may use different metadata sanitation, so both original and exported hashes must be retained. Every candidate asset's approved scope must refer to the bytes actually shipped.

## Personal Seed art in this snapshot

Native and Unity `hampton-liminal-seed-v1.png` and `hampton-liminal-garnet-v1.png` are current authored presentation resources. Their metadata-stripped exports retain the original image payload. They represent an appearance choice and do not ship Hampton's personal context, saved preferences or companion history. Their new-artwork licensing scope remains separate from the existing MIT code license and must be settled before publication of these art files.

## Newer files requiring explicit scope review

| Asset | Existing local provenance | Candidate status |
| --- | --- | --- |
| `unity/ARCHi/Assets/Resources/KIN/kin-arena-motion-v1.fbx` | `desktop/ArtSources/kin-arena-motion-v1/README.md` and manifest; locally authored First Light geometry and shape keys | Redistribution review pending; candidate has source-path metadata repaired and must pass Unity import qualification |
| `unity/ARCHi/Assets/Resources/KIN/kin-reference-v2.fbx` | `unity/ARCHi/Assets/Resources/KIN/refinement-provenance.json` | Redistribution review pending; candidate has source-path metadata repaired and must pass Unity import qualification |
| `unity/ARCHi/Assets/Resources/Proto/proto-archi-v1.fbx` | `desktop/ArtSources/proto-archi-v1/README.md` and manifest | Redistribution and reference scope pending |
| `unity/ARCHi/Assets/Resources/Proto/proto-archi-v2.fbx` | `desktop/ArtSources/proto-archi-v2/README.md` and manifest | Redistribution and reference scope pending |
| `unity/ARCHi/Assets/Resources/Proto/proto-character.fbx` | `unity/ARCHi/Assets/Resources/Proto/native-proto-provenance.json`; `desktop/ArtSources/proto-blender-v1/README.md` | Redistribution and supplied-reference scope pending |
| `unity/ARCHi/Assets/Resources/Proto/proto-light-v3.fbx` | Local `desktop/ArtSources/proto-light-v3/recipe.json` and manifest; the runtime provenance file now follows the newer revision | Redistribution and reference scope pending; current source/export hash is retained unchanged |
| `unity/ARCHi/Assets/Resources/Proto/proto-light-v4.fbx` | Current `unity/ARCHi/Assets/Resources/Proto/provenance.json`; local `desktop/ArtSources/proto-light-v4/recipe.json` and manifest | Redistribution and inherited source/reference scope pending; current exported bytes require new qualification |
| Native `archi-proto-blender-v1.png` and Unity `Proto/proto-body.png` | Same Proto authoring README and native Proto provenance | Redistribution/reference review pending; candidate strips text/EXIF without changing IDAT bytes |
| Native `archi-ball-of-light-v1.png` and Unity `Proto/archi-ball-of-light-v1.png` | Current Seed appearance resources; exact source/export hashes for both paths in this candidate's inventory | New runtime artwork scope pending; candidate strips text/EXIF without changing IDAT bytes |

The referenced authoring originals are retained locally, outside the source export. Their paths explain provenance and are not a promise that those files ship. The Proto authoring documentation describes local procedural modeling from a supplied concept and generated model sheet; that process description alone does not prove rights to all references.

The current source scope includes seven FBX files, their Unity `.meta` files and included provenance JSON. The final candidate manifest is authoritative if the source set changes again. The previous exporter did not include `.fbx`; do not use it unchanged. Exact prior approved asset bytes may retain their supported prior declaration; every new or changed asset remains pending until its own scope is supported. Hashes and these decisions appear in the candidate's review and preflight receipts.

The KIN Particle Seed choice is produced by native/Unity procedural source and shader code, with its source files and Unity metadata included. Selecting a Seed appearance does not create another individual, confer a license for separate references, or authenticate creator identity.

## Metadata and runtime integrity

Prior exports removed PNG `File` text chunks in exported copies while keeping compressed image data and scanlines identical. The current scan also identifies text and EXIF chunks for review. It reports metadata categories and byte locations without disclosing private values. A metadata finding is not automatically a credential disclosure.

This candidate removes PNG text/EXIF chunks and updates matching native/Unity digest pins and provenance; IDAT and every non-metadata chunk remain byte-identical. The two KIN FBX files change only the `Original|ApplicationNativeFile` string in SceneInfo metadata, at its existing byte width. Blender's installed parser verifies that exactly one typed property differs and every other parsed property, geometry array, byte and file length is unchanged. The original private value is not recorded in public files. Source/export hashes and parser identity are retained in the local preparation receipt. These checks still require native rendering and Unity import qualification on the exported bytes.

Coplay's embedded Editor package retains its own MIT notice. Unity, Blender, optional Reactor software and installed dependencies retain their own terms and notices. No engine installation, model weights, paid runtime, profiles or private assistant records are included in this source packet.

The Hampton Designed creator seal, canonical game eligibility, verified ownership, edition issuance and commerce are separate features and review decisions. This attribution draft adds no conditions to existing MIT code permissions and makes no claim that a local design hash authenticates an owner or creator.

## This code-only branch

The pending new artwork listed above is not distributed in this branch. Its code and provenance descriptions remain for review; those descriptions grant no artwork rights. Existing published assets retain the prior MIT scope, including metadata-only PNG exports. The omitted path inventory is in `docs/ALPHA_VALIDATION.md`.
