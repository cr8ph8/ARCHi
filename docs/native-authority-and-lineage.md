# Native authority and lineage

Owner decision, 2 October 2026: **ARCHi's local records are authoritative. WikiOS is a linked interface.** The same rule applies to a future ChatGPT companion panel.

## One authority, existing owners

The native app has several bounded domain journals. They are not one global database or an atomic transaction spanning every file. Unification means each value has one owner and cross-domain references identify the exact record and revision. It does not mean copying every value into an additional ledger. These local validation and revision controls are not a cryptographically attested global history or protection against a process that can rewrite the account's files.

| Record | Existing canonical owner | What an interface may do |
|---|---|---|
| Companion identity and selected profile | `CompanionProfiles` | Resolve an explicit profile ID; a matching name or picture does not establish identity. |
| Preferences, kept lessons, personal context, collected items | `NativePreferenceDocument` through `CompanionStore` | Read current authorized records; submit changes through the existing validation and stale-baseline checks. |
| Retained sources, compiled knowledge pages and reviewed relationships | `ReadingSourceLibrary` | Navigate exact IDs/revisions/digests and show their sources, status and backlinks. |
| Task dispatch, resource observations and attributable outcomes | `TokenStewardStore` | Inspect the existing task and its captured source/page references; do not create another task-history owner. |
| Document proposals, apply/revert history and feedback | `DocumentWorkJournal` | Link the task and exact document revisions; obtain acceptance from the existing document workflow. |
| Development and Q2E observations | Existing domain admission paths and controller | Evaluate candidates separately from admitting outcomes. Rendering, replay and model confidence confer no learning credit. |
| Project changes and delivery evidence | `PROJECT_ACCOUNTABILITY.md` and its evidence receipts | Describe what was built, installed and checked. These are engineering records, not the runtime source of personal truth. |

Memory-map particles and WikiOS pages are views of records. Filtering, animation, export, reopening or indexing does not create additional memories or change their authority. Source correction/removal must be resolved against the current source owner, even when a historical task still retains the old dependency identifiers.

## Task provenance

The core assurance increment retains exact local source and knowledge-page bindings in the existing task record before dispatch. These bindings contain identifiers, revisions and digests, not copied source text. Identical retries are idempotent; a different binding cannot silently replace the first. Earlier tasks without these fields remain **provenance unrecorded**.

This record says which input versions were captured. It does not prove that the model used them correctly, that every answer assertion is supported, or that the source remains current. Provider completion, source citation, user feedback and checked outcome remain distinct evidence. Graph links open the source/page owner for inspection; they do not automatically select an exact historical page revision.

## Acquisition and title evidence

Collected Marketplace items retain their exact package identity alongside the acquired listing/version and publisher declaration in the native preference owner. A manually imported or older item has no fabricated acquisition history. Removal removes the locally attached acquisition evidence with the item; this is not a permanent legal title registry.

A supplied publisher rights declaration is **not verified legal title**. This increment does not establish an upstream assignment chain, exclusive ownership, sublicensing rights, payment settlement, publisher identity verification or cryptographic publisher signatures. Those need actual documents and verification. The current development catalog must not be presented as settled production commerce.

## WikiOS and companion-plugin contract

These are integration requirements, not a claim that a new plugin has been connected:

1. Resolve the authenticated account and explicit native profile before reading. Apply record-level sharing scope; do not send a complete private profile as ambient model context.
2. Return qualified records with owner, stable ID, revision, source linkage and status. Display unavailable or stale evidence instead of rebuilding authoritative state from a summary.
3. Keep bounded Q2E candidate evaluation pure. A candidate is not an accepted change.
4. Route writes through native owner operations with an expected revision, evidence references and a replay-safe outcome ID. A model saying "reviewed" is not proof of human review.
5. Show only acknowledged revisions. Undo uses the domain's existing correction/reversal rules; it cannot undo an external message or retroactively erase another party's observation.
6. Keep credentials, opaque provider continuation artifacts and raw hidden activations outside saved lesson, page and public export fields.

OpenAI's current plugin documentation supports MCP tools and sidebar/conversation panels and requires authorization in the server. Tool annotations do not replace that enforcement. The native Pet's behavior remains a separate host interface; this work does not add a Pet state hook. Sources checked 2 October 2026: [MCP server](https://developers.openai.com/plugins/build/mcp-server), [extensions](https://developers.openai.com/plugins/build/extensions).

## Cleanup and remaining work

Three identical redirect-denial delegates now share `HTTPNoRedirectPolicy`; destination validation and response checks stay in their active transports. The inspected domain stores, receipt types and UI consumers are active and serve different purposes. No whole subsystem was deleted merely because its name resembled another one.

The current native journals still lack a global cross-file transaction. New clients need an authenticated adapter and explicit recovery across owner operations; a second writable WikiOS or plugin database would make that worse. Cross-device synchronization, plugin connection, comprehensive title verification and beta acceptance remain open. See [core assurance and evidence](core-assurance-2026-10-02.md) for the actual delivery status.
