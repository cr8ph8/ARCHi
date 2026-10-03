# Source-linked knowledge pages

ARCHi's Memories screen now holds user-authored **claims** and **concepts** alongside their exact supporting passages. It uses the existing profile's ReadingSourceLibrary; Activity map is a derived view of that owner. No second app, vault, companion or model service is created.

## Working flow

1. Keep a reading copy in Work together, or use Add text file in Memories.
2. Choose New page. Write a title and note, choose Claim or Concept, and link one to four exact passages. Repeated quotations require choosing the occurrence. Using the entire kept copy is an explicit choice.
3. Save the draft, inspect its evidence, then Mark reviewed. This records your review, not factual certification.
4. Open the page from Activity map, revise it, inspect earlier versions, withdraw it, or explicitly Copy Markdown.
5. Choose **Use in local chat** on a current reviewed page. Select up to four pages, then review the selection and press Send in Chat. Selection alone sends nothing. See [local knowledge chat](native-knowledge-chat.md) for its routing and context limits.

Pages are searchable by title, note, kind and state. Profile switching, restoration and normal Quit protect an open draft. Saving never overwrites the currently shared working copy. Copy Markdown writes to the macOS clipboard, which may be available to other apps and Universal Clipboard according to system settings.

## Exact dependency and correction rules

An anchor contains the retained source UUID, revision, SHA-256 digest, UTF-16 location/length and SHA-256 digest of the quoted passage. It stores no extra source text or original file path. Unicode boundaries and all ranges are validated. A page review binds the exact immutable page revision.

Source replacement or forgetting makes dependent reviewed pages unavailable for current use. The page keeps its authored note and hash/range references; unavailable source prose is never reconstructed. Make a new draft with fresh anchors before reviewing again. Withdrawing a page appends a revision; it is not erasure of authored history.

The graph shows page-to-source attribution and current [reviewed page connections](native-reviewed-connections.md). Supports, Contradicts and Depends on are directed user declarations, not proof of entailment. Shared sources give inspectable backlinks.

## Persistence and bounds

The existing `preferences.reading-sources.json` uses v2 for page history, v3 when relationship records are present, v4 when source provenance is retained, and v5 after a page connection is saved. Legacy v1–v4 files load without writes; explicit edits choose the required schema. V4 adds [source origin and derivation](native-source-provenance.md) to the same atomic owner. Older binaries cannot read newer schemas; preserve the installed app rollback and data backup when intentionally downgrading.

Bounds: eight kept copies, 100 KB per source, 400 KB total source text; page title 240 UTF-8 bytes, note 8,192 UTF-8 bytes, one to four anchors, 64 total page versions. Each active page reserves a future withdrawal slot. Full history is preserved and reported; no automatic pruning. File locking and exact disk-digest checks prevent stale windows from overwriting each other. Malformed schemas, duplicate keys and invalid histories block writes.

The native profile backup already includes `preferences.reading-sources.json`. Its source copies, page versions and connection history travel together as one exact-byte file, including explicit file absence. The earlier statement that this library was excluded was incorrect. Backup bounds now match the library's 8 MiB file ceiling, the outer envelope accounts for base64, and the restore summary reports page-version count. Use [Backup & restore](native-desktop-backup-and-restore.md) for a profile checkpoint; Markdown copy is a separate inspectable export, not a replacement for revision history.

## Hampton placement and present limit

This installs source-addressed authored memory and correction-aware dependency navigation in the existing native memory owner. It complements the already source-bound kept lessons and document methods. It does not conflate an authored claim, user review, an observed task outcome, or a certified skill.

Explicitly selected reviewed pages can now inform local Qwen chat. Their exact page and source dependencies are checked before dispatch, while admitting the reply, and before follow-up reuse. The page/quote context block is limited to 16 KiB; it is never silently shortened. The existing shared document remains unchanged and is excluded from this page request. External routes and fallback are blocked for page-dependent context.

Page selection does not create facts, retain a lesson, or award companion growth. A separately reviewed lesson kept from a page answer retains its page/source dependencies and is restricted to Chat. It cannot become a document-revision method through this route. Automatic page synthesis, semantic retrieval, entailment verification, transferable skill certification and research-theory validation remain separate work.

See [knowledge links](native-knowledge-links.md) for the source-grounded navigation design and [connected reading](native-connected-reading.md) for existing source-assisted document reasoning. Authoring, review, graph navigation and backup require no model call; sending a page question invokes the configured local Qwen route.
