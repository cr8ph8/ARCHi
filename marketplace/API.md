# Creator marketplace API v1

This is a persistent **development service**, available only at `http://127.0.0.1:47831` by default. Publishing makes a recipe discoverable in this running local service. It does not publish it to the Internet. Start an empty database explicitly; no account or catalog is seeded from a person's ARCHi profile.

JSON request bodies use UTF-8, `Content-Type: application/json`, and at most 16,384 bytes. Duplicate JSON keys, unknown fields, invalid enum values and non-finite numbers are rejected. Native clients send `Authorization: Bearer <token>` for authenticated routes. There are no cookies or browser CORS permissions. All timestamps are UTC ISO-8601 strings, e.g. `2026-09-16T22:00:00Z`.

## Routes

| Method and route | Request | Response |
| --- | --- | --- |
| GET `/v1/health` | None | `{service:"archi-marketplace",apiVersion:1,mode:"development",commerce:false,recipeSchema:"archi-item-design/v1",maximumRecipeBytes:4096}` |
| POST `/v1/accounts` | `{handle,displayName,password}` | 201 `{account}`; does not sign in |
| POST `/v1/sessions` | `{handle,password}` | 201 `{account,token,expiresAt}` |
| GET `/v1/me` | Bearer | `{account}` |
| DELETE `/v1/sessions/current` | Bearer; no body | `{signedOut:true}` |
| POST `/v1/listings` | Bearer; `{recipe,provenance}` | 201 `{listing}`; creates a draft |
| GET `/v1/me/listings?limit=40&offset=0` | Bearer | `{items,total,limit,offset}`; latest version of each owned listing |
| GET `/v1/catalog?q=&limit=40&offset=0` | None or Bearer | `{items,total,limit,offset}`; current published versions only |
| GET `/v1/listings/{id}` | None or Bearer | `{listing}`; latest version to owner, current published version to others |
| PUT `/v1/listings/{id}` | Bearer; `{expectedVersion,recipe,provenance}` | `{listing}`; adds a draft version |
| POST `/v1/listings/{id}/publish` | Bearer; `{expectedVersion}` | `{listing}`; publishes latest draft in this service |
| POST `/v1/listings/{id}/archive` | Bearer; `{expectedVersion}` | `{listing}`; hides the whole listing from the catalog |
| GET `/v1/listings/{id}/versions?limit=40&offset=0` | Owner's Bearer | `{items,total,limit,offset}`; newest first |
| GET `/v1/listings/{id}/versions/{version}/package` | None or Bearer | Raw closed recipe JSON, **not an envelope**; only the current published version, an owned version, or a previously acquired exact version |
| POST `/v1/inventory` | Bearer; `{listingID,version,recipeID}` | 201 `{entry,alreadyAcquired:false}` or 200 `{entry,alreadyAcquired:true}` |
| GET `/v1/inventory?limit=40&offset=0` | Bearer | `{items,total,limit,offset}`; immutable acquired snapshots, newest first |

`limit` is 1–100 and `offset` is 0–10,000. Unknown/repeated query parameters fail. Query `q` is a literal, case-insensitive search across title, summary, declared creator, publisher handle and publisher display name, at most 100 UTF-16 units. Search does not interpret SQL wildcards. The limits apply to catalog, inventory, owned listings and history independently. Results use a stable order for a given database state; refresh after a mutation before continuing offset pagination.

## Response objects

`account`/`publisher`: `{id,handle,displayName,createdAt}`. IDs are random UUID strings. Handles are 3–32 lowercase ASCII letters/digits/underscores, starting with a letter; surrounding whitespace and uppercase are not silently changed. `displayName` is 1–48 UTF-16 units. Passwords are 12–128 Unicode scalar values, at most 512 UTF-8 bytes, with no control characters. Accounts represent a local sign-in, **not verified real-world identity or a verified rights holder**. Sessions expire after 12 hours; logging out revokes that exact token. Passwords and bearer tokens are never included in listings, logs or other responses.

`listing`:

```json
{
  "id": "random-uuid",
  "version": 2,
  "status": "published",
  "publishedVersion": 2,
  "publisher": {"id":"random-uuid","handle":"synthetic_creator","displayName":"Synthetic Creator","createdAt":"2026-09-16T22:00:00Z"},
  "recipeID": "64-lowercase-hex-fingerprint",
  "recipe": {},
  "provenance": {"declaration":"original","attribution":"Synthetic test design by Synthetic Creator","source":"","rightsConfirmed":true},
  "createdAt": "2026-09-16T22:00:00Z",
  "updatedAt": "2026-09-16T22:00:00Z"
}
```

`recipe` is the exact existing `CompanionItemPackage` JSON object (shown as `{}` above only for readability). It requires exactly `schema,title,creator,summary,revision,license,palette,crown,action,defaultGesture`. `schema` is `archi-item-design/v1`; `revision` is integer 1–999. License: `MIT`, `CC0`, `CC-BY-4.0`; palette: `lilac,mint,gold,rose,ice`; crown: `pearl,star,leaf`; action: `decoration,pointSelection`. Nested gesture requires exactly `pace` (`Quick,Gentle,Unhurried`), `sparkle` (`None,Soft,Bright`), and `hold` (`Brief,Lingering`). The native UTF-16 text limits and control-character exclusions apply. Serialized recipe must be at most 4,096 bytes. The server computes `recipeID` using the existing length-prefixed `archi-item-design-canonical/v1` fingerprint, never a caller-provided ID.

`provenance` requires exactly four fields. `declaration` is `original` or `licensed-adaptation`; `attribution` is nonempty, at most 500 UTF-16 units; `source` is plain attribution/source text at most 500 UTF-16 units (required nonempty for adaptations); `rightsConfirmed` must be boolean `true`. This records the publisher's declaration of permission to distribute under `recipe.license`; it does not independently verify rights, import arbitrary assets, or grant bundled-registry membership or Arena effects. Source text is not fetched or executed.

`entry`: `{id,listingID,version,recipeID,recipe,publisher,provenance,acquiredAt}`. Recipe and provenance are the exact acquired version. The inventory deduplicates `(accountID,recipeID)` across listings and returns the original entry on repeat acquisition. An acquisition is free access to a copyable recipe, not a purchase, exclusive ownership, an edition or equipment activation. Service inventory is separate from the native eight-design installed collection. The app must explicitly validate and admit the downloaded recipe before installation and must keep Equip a separate action.

## Versioning, visibility and retry behavior

Every successful listing mutation advances `version`: draft 1 → published 2 → edited draft 3 → published 4, for example. Recipe, provenance, status and version timestamp snapshots are immutable. The recipe's authored `revision` is separate. `expectedVersion` always names the latest listing version; stale updates fail with 409 `version_conflict` without writes. Editing keeps any previously published version in the catalog until a new deliberate publish. `publishedVersion` is the listing's **current** public version number or `null`, including in historical responses. It is not a frozen snapshot field and may be greater than a historical snapshot's `version` (history version 1 may show current `publishedVersion:4`). Publishing requires a draft. Archiving creates an archived version, clears the public version and prevents new downloads/acquisitions by unentitled visitors. Previously acquired versions remain in that account's inventory and are downloadable. Edit an archived listing to make a new draft before publishing again.

Send `Idempotency-Key: <UUID>` on authenticated POST/PUT listing mutations and acquisition. It is optional but recommended. A committed response is stored transactionally with its operation and request-body digest, scoped to the signed-in account. Retrying the same key/operation/body returns that response; reusing it with different input returns 409 `idempotency_conflict`. Keys are retained with this development database. They are not accepted on account/session routes. Acquisition also deduplicates independently of the key.

Cancel before submission has no effect. A timeout or transport cancellation after submission **cannot prove the server did not commit**. Retry with the original idempotency key or refresh the owned listing/inventory; do not invent a rollback or report success before a confirmed response. An unknown token, expired session or revoked session returns 401 `unauthorized`. Discard invalid sessions and sign in again. Resource ownership is always checked on the server. Private/missing listings are reported as 404 `not_found`; acquisition of a changed/unavailable public version returns 409 `listing_changed`.

Errors use `{error:{code,message},requestID}` with stable codes: `invalid_request` (400), `unauthorized` (401), `origin_forbidden`/`host_forbidden` (403), `not_found` (404), `method_not_allowed` (405), `handle_taken`/`version_conflict`/`state_conflict`/`listing_changed`/`idempotency_conflict` (409), `body_too_large` (413), `unsupported_media_type` (415), `validation_failed` (422), `capacity_reached`/`rate_limited` (429), `storage_unavailable` (503). Validation errors describe constraints without echoing passwords, tokens or submitted values. Responses always have `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, and a request ID. Recipe downloads add `X-ARCHi-Recipe-ID` and an attachment filename based only on that validated digest.

There are no price, balance, currency, payment, checkout, external-publication, provider-authentication or executable-package endpoints.
