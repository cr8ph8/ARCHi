# ARCHi creator marketplace

A persistent local creator service for accounts, draft/published/archived listing history, catalog search, validated recipe downloads and acquired inventory. SQLite owns service state. The native app owns installed recipes, saved companion preferences and equipment. Nothing is imported from a person's ARCHi profile automatically.

From the repository root, with Python 3.11 or newer:

```sh
python3 -m unittest discover -s marketplace/tests -v
python3 -m marketplace --database marketplace/data/development.sqlite3
```

The first command uses only synthetic data in disposable directories and loopback servers on ephemeral ports. The second starts an empty persistent service at `http://127.0.0.1:47831`. The database argument is required; `--port` can select another port. The native Marketplace must use the same port. Stop with Ctrl-C and restart with the same database path to retain accounts, sessions, listing versions and inventory. No dependency installation, schema seeding, companion profile access or external connection is part of startup.

The database is private local state, created with mode `0600`. Existing symlinks, permissive files and unrelated schema tables are rejected. `marketplace/data/`, SQLite files, journals and caches are excluded from source export; do not put actual profiles or credentials in fixtures. Keep any backup private. Copy the database only after stopping the server; this implementation uses SQLite's transactional rollback journal and is a single-process development service.

## Creator workflow

1. Start the local service, connect from Marketplace, then create a development account and sign in. Use a separate development password. Accounts are local handles, not verified identities.
2. Create a closed ARCHi recipe, choose its declared license, record attribution and provenance, and explicitly confirm permission to distribute it under that license.
3. Save a draft. Review it, then publish into this local service's catalog. Another local account can search the catalog and acquire that exact version.
4. Download the validated recipe and explicitly add it to the app's local collection. Equip remains a separate app action. Service inventory can hold more recipes than the app's eight-design installed collection.
5. Edit a published listing to create a new draft. Its previous published version stays available until deliberate republishing. Archive hides it from new discovery/acquisition; previous collectors retain their acquired copy.

The [API contract](API.md) specifies exact requests, responses, validation, version conflicts and retry behavior. Every listing mutation creates an immutable content/status snapshot. Acquisition is unique by account and recipe fingerprint. It does not create ownership, scarcity, bundled registration, learned knowledge or canonical Arena effects.

## Persistence and recovery

Listing mutations and acquisitions run in SQLite transactions. Optional UUID idempotency keys persist the successful response with the operation and input digest in the same transaction. A disconnected request may already have committed; retry using its original key or refresh before continuing. Never report a canceled transport as a confirmed rollback. Native local installation can fail independently, for example if the eight-design collection is full; the acquired service copy remains available.

Authentication uses random 32-byte session secrets with only SHA-256 token digests in storage. Sessions expire after 12 hours and logout revokes the current session. Passwords use a unique 32-byte salt and scrypt (`N=32768,r=8,p=3`, 32-byte result), one of the documented OWASP configurations. Password bytes are never truncated. Unknown-handle and wrong-password login failures use the same response and password-hashing work. [OWASP password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)

The service binds only `127.0.0.1`, validates the exact Host/port, rejects browser Origin requests and sends no CORS permissions or cookies. It never logs request paths, bodies, credentials or tokens. Requests, query length, pagination, sessions and stored object counts are bounded. All resource ownership is checked server-side; creator text in a recipe grants no account privileges. Downloaded bytes are revalidated against the stored native-compatible recipe fingerprint.

Development caps are 100 accounts, 100 listings per account, 1,000 versions per listing, 1,000 acquired recipes per account, 10,000 idempotent responses per account and 20 active sessions per account. Account/sign-in requests share a 20-per-minute process-local throttle. Old login throttles reset on process restart; idempotency responses do not expire. These explicit limits keep a local test service bounded. There is no account/password recovery or destructive catalog administration interface yet.

## Release boundary

The HTTP adapter uses Python's standard library and is deliberately restricted to native development use on one machine. Python does not recommend `http.server` as a production server. Internet hosting would require a separately reviewed transport/deployment design, authenticated server identity, abuse controls, account recovery, rights moderation, operational backup/recovery and cross-user acceptance. None of those are implied by passing this local suite. [Python HTTP server documentation](https://docs.python.org/3/library/http.server.html)

No currency, balances, checkout, payment flow, executable packages, external publication or verified creator badges are implemented. Publishing here means local catalog visibility only. Human UI acceptance, fresh-install acceptance and broader native/Unity qualification are recorded separately from the backend's tests.
