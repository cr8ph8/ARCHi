# Source origin and derivation in ARCHi

In **Work together → Reading library**, use **Paste text…**, **Add text file…**, or **Keep current copy**. The direct paste sheet accepts a title up to 240 UTF-8 bytes and text up to 100 KB. Typing is temporary; **Keep copy** saves locally and sends nothing.

Open **Source details…** beside a kept copy. Record its origin (unknown, human authored, AI generated, or mixed), how it arrived, an optional attribution note, and up to four exact parent copies. Saving is explicit; opening or cancelling the sheet changes nothing.

These fields are user declarations. ARCHi does not infer authorship from prose, verify an author, or certify that a publication or generated answer is true. New imported copies have unknown authorship. Existing v1–v3 copies remain undeclared/unknown and are not rewritten merely by opening the library.

## What an edit changes

Source details belong to the existing local reading library, not another app or memory store. The v4 archive retains the declaration and its timestamp. A change advances the source revision even when the text is identical. The text SHA-256 remains a hash of the original text; a separate provenance SHA-256 covers the declaration.

Exact source bindings carry typed origin, acquisition, parent identities and the provenance digest into knowledge-page anchors, reading plans, retained reading traces and lesson origins. Page-bound procedures retain their existing page-version dependency. Free-text attribution remains in the source owner; it is excluded from model summaries and task receipts.

The local model receives an optional declaration summary with its existing quoted passages. No new model route, cloud disclosure, inference call or automatic memory admission is enabled. Ordinary knowledge-chat lane receipts remain transient; this increment does not add a new persistent journal for every chat.

## Corrections and reuse

An attached parent includes its exact ID, revision, text digest and optional provenance digest. At use time, ARCHi walks the bounded dependency graph. A changed or forgotten parent makes the derived source unavailable for selection, search, quotation, exact table lookup and downstream page/method reuse. Further descendants are checked recursively.

Copies and notes remain inspectable. Forgetting a parent does not silently delete its children or substitute a newer parent. Open Source details, explicitly remove a stale parent, attach the appropriate current version, then review dependent notes/methods. This is a human correction workflow, not automatic re-certification.

Replacing a kept text copy resets its authorship to unknown and preserves any previously attached parents until explicit review. Metadata edits reject missing/stale parents, self-dependence and circular derivation. Existing limits remain eight sources, 400 KB of source text and four parents per copy. The library does not automatically archive old text revisions or watch original files.

## Hampton integration and evidence limits

This installs source-qualified memory into the existing observation, memory, method and request ownership chain. It applies Hampton's separation of observation, inference and admitted reuse. The [September research intake](research/2026-09-27-evidence-diversity-and-retrieval/README.md) supplies the evidence context: generated material must retain its derivation, and a valid retrieval address is distinct from a supported answer.

This is provenance infrastructure, not a trained STAIR model, a model-collapse prevention proof, a biological inference engine, or new validation of the entire Hampton stack. Source type alone neither grants authority nor excludes useful generated material. Real usefulness still requires attributable outcomes and review.

Implementation: `ReadingSourceProvenance.swift`, `ReadingSourceLibrary.swift`, `ReadingSourceLibraryViews.swift`, `ReadingSourceProvenanceEditor.swift`; consumers include document reading, knowledge retrieval, page contexts, table lookup and the existing procedure availability checks.

See [Evidence beside an answer](native-answer-evidence.md) for the captured source view and the distinction between prepared, dispatched and cited text.
