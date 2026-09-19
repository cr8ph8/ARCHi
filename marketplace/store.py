"""SQLite authority for accounts, immutable recipe listings and acquired copies."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import stat
import time
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from . import API_VERSION, SERVICE_NAME
from .model import (APIError, MAX_RECIPE, RECIPE_SCHEMA, Response, exact_keys, handle_value,
                    integer, json_bytes, password_value, text_value, validate_provenance,
                    validate_recipe)

SESSION_SECONDS = 12 * 60 * 60
MAX_ACCOUNTS = 100
MAX_LISTINGS = 100
MAX_VERSIONS = 1000
MAX_INVENTORY = 1000
MAX_IDEMPOTENCY = 10_000
SCRYPT_N, SCRYPT_R, SCRYPT_P = 2**15, 8, 3
SCHEMA = """
CREATE TABLE accounts (
 id TEXT PRIMARY KEY, handle TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
 password_salt BLOB NOT NULL, password_hash BLOB NOT NULL, created_at TEXT NOT NULL
);
CREATE TABLE sessions (
 token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
 expires_at REAL NOT NULL, created_at TEXT NOT NULL
);
CREATE INDEX sessions_account ON sessions(account_id);
CREATE TABLE listings (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES accounts(id),
 latest_version INTEGER NOT NULL, published_version INTEGER, created_at TEXT NOT NULL
);
CREATE INDEX listings_owner ON listings(owner_id);
CREATE TABLE versions (
 listing_id TEXT NOT NULL REFERENCES listings(id), version INTEGER NOT NULL,
 status TEXT NOT NULL CHECK(status IN ('draft','published','archived')),
 recipe_id TEXT NOT NULL, recipe_json TEXT NOT NULL, provenance_json TEXT NOT NULL,
 created_at TEXT NOT NULL, PRIMARY KEY(listing_id,version)
);
CREATE TABLE inventory (
 id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id),
 listing_id TEXT NOT NULL, version INTEGER NOT NULL, recipe_id TEXT NOT NULL,
 acquired_at TEXT NOT NULL, UNIQUE(account_id,recipe_id),
 FOREIGN KEY(listing_id,version) REFERENCES versions(listing_id,version)
);
CREATE TABLE idempotency (
 account_id TEXT NOT NULL REFERENCES accounts(id), key TEXT NOT NULL,
 request_hash TEXT NOT NULL, status INTEGER NOT NULL, response_json TEXT NOT NULL,
 PRIMARY KEY(account_id,key)
);
PRAGMA user_version=1;
"""


def timestamp(seconds: float) -> str:
    return datetime.fromtimestamp(seconds, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def hash_password(password: bytes, salt: bytes) -> bytes:
    # OWASP's 32 MiB / p=3 scrypt configuration; no third-party runtime dependency.
    return hashlib.scrypt(password, salt=salt, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P,
                          maxmem=64 * 1024 * 1024, dklen=32)


def capacity(condition: bool, label: str) -> None:
    if condition:
        raise APIError(429, "capacity_reached", f"This development database has reached its {label} limit.")


def not_found() -> None:
    raise APIError(404, "not_found", "That resource is unavailable to this account.")


class Store:
    def __init__(self, path: str | Path, *, clock=time.time):
        self.path = Path(path).absolute()
        self.clock = clock
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Refuse permissive/symlink database paths instead of altering an existing file.
        descriptor = os.open(self.path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise ValueError("Use a regular database owned by this user with mode 0600.")
        finally:
            os.close(descriptor)
        with self.connection() as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
            if version == 0:
                if db.execute("SELECT 1 FROM sqlite_master WHERE type='table'").fetchone():
                    raise ValueError("Refusing an existing database without the marketplace schema.")
                db.executescript("BEGIN IMMEDIATE;" + SCHEMA + "COMMIT;")
            elif version != 1:
                raise ValueError("This service cannot open that marketplace schema version.")
            expected = {"accounts", "sessions", "listings", "versions", "inventory", "idempotency"}
            actual = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if actual != expected:
                raise ValueError("Marketplace database tables do not match schema version 1.")
        self._dummy_salt = secrets.token_bytes(32)
        self._dummy_hash = hash_password(secrets.token_bytes(32), self._dummy_salt)

    @contextmanager
    def connection(self, *, write=False):
        db = sqlite3.connect(self.path, timeout=3, isolation_level=None)
        db.row_factory = sqlite3.Row
        try:
            db.execute("PRAGMA foreign_keys=ON")
            db.execute("PRAGMA busy_timeout=3000")
            db.execute("BEGIN IMMEDIATE" if write else "BEGIN")
            yield db
            if db.in_transaction:
                db.commit()
        except BaseException:
            if db.in_transaction:
                db.rollback()
            raise
        finally:
            db.close()

    @staticmethod
    def _account(row) -> dict:
        return {"id": row["id"], "handle": row["handle"], "displayName": row["display_name"],
                "createdAt": row["created_at"]}

    def _authenticate(self, db, token: str | None, *, required=False):
        if token is None and not required:
            return None
        row = None
        if isinstance(token, str) and re.fullmatch(r"[A-Za-z0-9_-]{43}", token):
            digest = hashlib.sha256(token.encode("ascii")).hexdigest()
            row = db.execute("""SELECT a.* FROM accounts a JOIN sessions s ON a.id=s.account_id
                                WHERE s.token_hash=? AND s.expires_at>?""", (digest, self.clock())).fetchone()
        if row is None:
            raise APIError(401, "unauthorized", "Sign in again; this session is unavailable or expired.")
        return row

    def _create_account(self, db, body):
        exact_keys(body, {"handle", "displayName", "password"})
        handle = handle_value(body["handle"])
        display = text_value(body["displayName"], 48, "Display name")
        password = password_value(body["password"])
        capacity(db.execute("SELECT count(*) FROM accounts").fetchone()[0] >= MAX_ACCOUNTS, "account")
        salt = secrets.token_bytes(32)
        digest = hash_password(password, salt)
        if db.execute("SELECT 1 FROM accounts WHERE handle=?", (handle,)).fetchone():
            raise APIError(409, "handle_taken", "That local handle is already registered. Sign in or choose another.")
        account_id, created = str(uuid.uuid4()), timestamp(self.clock())
        db.execute("INSERT INTO accounts VALUES (?,?,?,?,?,?)", (account_id, handle, display, salt, digest, created))
        return Response(201, {"account": {"id": account_id, "handle": handle, "displayName": display, "createdAt": created}})

    def _sign_in(self, db, body):
        exact_keys(body, {"handle", "password"})
        handle, password = handle_value(body["handle"]), password_value(body["password"])
        row = db.execute("SELECT * FROM accounts WHERE handle=?", (handle,)).fetchone()
        digest = hash_password(password, row["password_salt"] if row else self._dummy_salt)
        if not hmac.compare_digest(digest, row["password_hash"] if row else self._dummy_hash) or row is None:
            raise APIError(401, "unauthorized", "The handle or password is incorrect.")
        now = self.clock()
        db.execute("DELETE FROM sessions WHERE expires_at<=?", (now,))
        capacity(db.execute("SELECT count(*) FROM sessions WHERE account_id=?", (row["id"],)).fetchone()[0] >= 20,
                 "active sessions per account")
        token = secrets.token_urlsafe(32)
        expires = now + SESSION_SECONDS
        db.execute("INSERT INTO sessions VALUES (?,?,?,?)",
                   (hashlib.sha256(token.encode("ascii")).hexdigest(), row["id"], expires, timestamp(now)))
        return Response(201, {"account": self._account(row), "token": token, "expiresAt": timestamp(expires)})

    @staticmethod
    def _page(query, *, search=False):
        if set(query) - ({"q", "limit", "offset"} if search else {"limit", "offset"}):
            raise APIError(400, "invalid_request", "This route has an unsupported query parameter.")
        result = []
        for key, default, minimum, maximum in (("limit", "40", 1, 100), ("offset", "0", 0, 10_000)):
            value = query.get(key, default)
            if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,5}", value):
                raise APIError(400, "invalid_request", "Use bounded integer pagination parameters.")
            result.append(integer(int(value), minimum, maximum, key))
        return tuple(result)

    @staticmethod
    def _root(db, listing_id):
        row = db.execute("SELECT * FROM listings WHERE id=?", (listing_id,)).fetchone()
        if row is None:
            not_found()
        return row

    @staticmethod
    def _content(row):
        try:
            recipe, digest = validate_recipe(json.loads(row["recipe_json"]))
            provenance = validate_provenance(json.loads(row["provenance_json"]))
            if digest != row["recipe_id"]:
                raise ValueError("Recipe fingerprint mismatch")
            return recipe, provenance
        except (ValueError, TypeError, APIError):
            raise APIError(503, "storage_unavailable", "A stored recipe failed validation. The database needs review.") from None

    def _listing(self, db, root, version=None):
        version = root["latest_version"] if version is None else version
        row = db.execute("SELECT * FROM versions WHERE listing_id=? AND version=?", (root["id"], version)).fetchone()
        if row is None:
            not_found()
        recipe, provenance = self._content(row)
        publisher = db.execute("SELECT * FROM accounts WHERE id=?", (root["owner_id"],)).fetchone()
        return {"id": root["id"], "version": version, "status": row["status"],
                "publishedVersion": root["published_version"], "publisher": self._account(publisher),
                "recipeID": row["recipe_id"], "recipe": recipe, "provenance": provenance,
                "createdAt": root["created_at"], "updatedAt": row["created_at"]}

    def _append_version(self, db, listing_id, version, status, recipe, provenance, *, published_version):
        _, digest = validate_recipe(recipe)
        validate_provenance(provenance)
        capacity(version > MAX_VERSIONS, "versions per listing")
        db.execute("INSERT INTO versions VALUES (?,?,?,?,?,?,?)", (listing_id, version, status, digest,
                   json_bytes(recipe).decode("utf-8"), json_bytes(provenance).decode("utf-8"), timestamp(self.clock())))
        db.execute("UPDATE listings SET latest_version=?,published_version=? WHERE id=?",
                   (version, published_version, listing_id))
        return self._listing(db, self._root(db, listing_id))

    def _new_listing(self, db, account, body):
        exact_keys(body, {"recipe", "provenance"})
        recipe, _ = validate_recipe(body["recipe"])
        provenance = validate_provenance(body["provenance"])
        capacity(db.execute("SELECT count(*) FROM listings WHERE owner_id=?", (account["id"],)).fetchone()[0] >= MAX_LISTINGS,
                 "listings per account")
        listing_id = str(uuid.uuid4())
        db.execute("INSERT INTO listings VALUES (?,?,1,NULL,?)", (listing_id, account["id"], timestamp(self.clock())))
        listing = self._append_version(db, listing_id, 1, "draft", recipe, provenance, published_version=None)
        return Response(201, {"listing": listing})

    def _change_listing(self, db, account, listing_id, action, body):
        root = self._root(db, listing_id)
        if root["owner_id"] != account["id"]:
            not_found()
        exact_keys(body, {"expectedVersion", "recipe", "provenance"} if action == "edit" else {"expectedVersion"})
        expected = integer(body["expectedVersion"], 1, MAX_VERSIONS, "Expected listing version")
        if expected != root["latest_version"]:
            raise APIError(409, "version_conflict", "The listing changed. Refresh it before saving or publishing.")
        latest = self._listing(db, root)
        if action == "publish" and latest["status"] != "draft":
            raise APIError(409, "state_conflict", "Only a draft can be published. Edit this listing to create a new draft.")
        if action == "archive" and latest["status"] == "archived":
            raise APIError(409, "state_conflict", "The listing is already archived.")
        recipe = body["recipe"] if action == "edit" else latest["recipe"]
        provenance = body["provenance"] if action == "edit" else latest["provenance"]
        new_version = root["latest_version"] + 1
        published = (new_version if action == "publish" else None if action == "archive" else root["published_version"])
        status = {"edit": "draft", "publish": "published", "archive": "archived"}[action]
        return Response(200, {"listing": self._append_version(db, listing_id, new_version, status, recipe,
                                                              provenance, published_version=published)})

    def _list_listings(self, db, account, query, *, catalog=False):
        limit, offset = self._page(query, search=catalog)
        if catalog:
            needle = text_value(query.get("q", ""), 100, "Search", required=False).strip().casefold()
            # Escape LIKE metacharacters: search text cannot become a wildcard program.
            term = "%" + needle.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"
            where = """l.published_version IS NOT NULL AND
                search_text(v.recipe_json,a.handle,a.display_name) LIKE ? ESCAPE '\\'"""
            args = (term,)
            version_join = "l.published_version"
        else:
            where, args, version_join = "l.owner_id=?", (account["id"],), "l.latest_version"
        base = f"""FROM listings l JOIN versions v ON v.listing_id=l.id AND v.version={version_join}
                   JOIN accounts a ON a.id=l.owner_id WHERE {where}"""
        def search_text(recipe_json, handle, display):
            recipe = json.loads(recipe_json)
            return " ".join([recipe["title"], recipe["summary"], recipe["creator"], handle, display]).casefold()
        db.create_function("search_text", 3, search_text, deterministic=True)
        total = db.execute("SELECT count(*) " + base, args).fetchone()[0]
        rows = db.execute("SELECT l.* " + base + " ORDER BY l.created_at DESC,l.id DESC LIMIT ? OFFSET ?",
                          (*args, limit, offset)).fetchall()
        return Response(200, {"items": [self._listing(db, r, r["published_version"] if catalog else None) for r in rows],
                              "total": total, "limit": limit, "offset": offset})

    def _entry(self, db, row):
        listing = self._listing(db, self._root(db, row["listing_id"]), row["version"])
        if listing["recipeID"] != row["recipe_id"]:
            raise APIError(503, "storage_unavailable", "A saved acquisition failed validation. The database needs review.")
        return {"id": row["id"], "listingID": row["listing_id"], "version": row["version"],
                "recipeID": row["recipe_id"], "recipe": listing["recipe"], "publisher": listing["publisher"],
                "provenance": listing["provenance"], "acquiredAt": row["acquired_at"]}

    def _acquire(self, db, account, body):
        exact_keys(body, {"listingID", "version", "recipeID"})
        if type(body["listingID"]) is not str or len(body["listingID"]) > 64:
            raise APIError(422, "validation_failed", "Listing ID must be a bounded string.")
        integer(body["version"], 1, MAX_VERSIONS, "Listing version")
        if type(body["recipeID"]) is not str or not re.fullmatch(r"[0-9a-f]{64}", body["recipeID"]):
            raise APIError(422, "validation_failed", "Recipe ID must be a lowercase SHA-256 fingerprint.")
        # An existing acquisition is immutable even if that listing was later archived.
        existing = db.execute("SELECT * FROM inventory WHERE account_id=? AND recipe_id=?",
                              (account["id"], body["recipeID"])).fetchone()
        if existing:
            return Response(200, {"entry": self._entry(db, existing), "alreadyAcquired": True})
        root = self._root(db, body["listingID"])
        if root["published_version"] != body["version"]:
            raise APIError(409, "listing_changed", "This version is no longer in the catalog. Refresh before acquiring it.")
        listing = self._listing(db, root, body["version"])
        if listing["recipeID"] != body["recipeID"]:
            raise APIError(409, "listing_changed", "The catalog recipe changed. Review the current version first.")
        capacity(db.execute("SELECT count(*) FROM inventory WHERE account_id=?", (account["id"],)).fetchone()[0] >= MAX_INVENTORY,
                 "inventory per account")
        entry_id = str(uuid.uuid4())
        db.execute("INSERT INTO inventory VALUES (?,?,?,?,?,?)", (entry_id, account["id"], root["id"], body["version"],
                   body["recipeID"], timestamp(self.clock())))
        row = db.execute("SELECT * FROM inventory WHERE id=?", (entry_id,)).fetchone()
        return Response(201, {"entry": self._entry(db, row), "alreadyAcquired": False})

    def _private_route(self, db, method, path, account, body, query):
        if path == "/v1/me" and method == "GET":
            return Response(200, {"account": self._account(account)})
        if path == "/v1/me/listings" and method == "GET":
            return self._list_listings(db, account, query)
        if path == "/v1/listings" and method == "POST":
            return self._new_listing(db, account, body)
        if path == "/v1/inventory":
            if method == "POST":
                return self._acquire(db, account, body)
            if method == "GET":
                limit, offset = self._page(query)
                total = db.execute("SELECT count(*) FROM inventory WHERE account_id=?", (account["id"],)).fetchone()[0]
                rows = db.execute("""SELECT * FROM inventory WHERE account_id=?
                                    ORDER BY acquired_at DESC,id DESC LIMIT ? OFFSET ?""",
                                  (account["id"], limit, offset)).fetchall()
                return Response(200, {"items": [self._entry(db, r) for r in rows], "total": total,
                                      "limit": limit, "offset": offset})
        match = re.fullmatch(r"/v1/listings/([a-f0-9-]{36})(?:/(publish|archive|versions))?", path)
        if match:
            listing_id, action = match.groups()
            if action is None and method == "PUT":
                return self._change_listing(db, account, listing_id, "edit", body)
            if action in {"publish", "archive"} and method == "POST":
                return self._change_listing(db, account, listing_id, action, body)
            if action == "versions" and method == "GET":
                root = self._root(db, listing_id)
                if root["owner_id"] != account["id"]:
                    not_found()
                limit, offset = self._page(query)
                rows = db.execute("SELECT version FROM versions WHERE listing_id=? ORDER BY version DESC LIMIT ? OFFSET ?",
                                  (listing_id, limit, offset)).fetchall()
                return Response(200, {"items": [self._listing(db, root, r[0]) for r in rows],
                                      "total": root["latest_version"], "limit": limit, "offset": offset})
        not_found()

    def dispatch(self, method: str, path: str, *, body=None, query=None, token=None, idempotency_key=None) -> Response:
        query = query or {}
        mutation = method in {"POST", "PUT", "DELETE"}
        paginated = path in {"/v1/catalog", "/v1/me/listings", "/v1/inventory"} or path.endswith("/versions")
        if query and (method != "GET" or not paginated):
            raise APIError(400, "invalid_request", "This route does not accept query parameters.")
        if method not in {"GET", "POST", "PUT", "DELETE"}:
            raise APIError(405, "method_not_allowed", "Use a documented API method.")
        if idempotency_key is not None:
            if not mutation or path in {"/v1/accounts", "/v1/sessions", "/v1/sessions/current"}:
                raise APIError(400, "invalid_request", "Idempotency keys apply only to listing and acquisition mutations.")
            if not isinstance(idempotency_key, str) or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", idempotency_key):
                raise APIError(400, "invalid_request", "Use a UUID idempotency key.")
            idempotency_key = idempotency_key.lower()
        with self.connection(write=mutation) as db:
            account = self._authenticate(db, token)
            if path == "/v1/health" and method == "GET":
                return Response(200, {"service": SERVICE_NAME, "apiVersion": API_VERSION, "mode": "development",
                                      "commerce": False, "recipeSchema": RECIPE_SCHEMA, "maximumRecipeBytes": MAX_RECIPE})
            if path == "/v1/accounts" and method == "POST":
                return self._create_account(db, body)
            if path == "/v1/sessions" and method == "POST":
                return self._sign_in(db, body)
            if path == "/v1/catalog" and method == "GET":
                return self._list_listings(db, account, query, catalog=True)
            match = re.fullmatch(r"/v1/listings/([a-f0-9-]{36})(?:/versions/([0-9]{1,4})/package)?", path)
            if match and method == "GET":
                listing_id, requested_version = match.groups()
                root = self._root(db, listing_id)
                owner = account is not None and account["id"] == root["owner_id"]
                version = int(requested_version) if requested_version else root["latest_version"] if owner else root["published_version"]
                acquired = account is not None and requested_version is not None and db.execute(
                    "SELECT 1 FROM inventory WHERE account_id=? AND listing_id=? AND version=?",
                    (account["id"], listing_id, version)).fetchone()
                if version is None or (not owner and version != root["published_version"] and not acquired):
                    not_found()
                listing = self._listing(db, root, version)
                if requested_version:
                    return Response(200, listing["recipe"], {"X-ARCHi-Recipe-ID": listing["recipeID"],
                        "Content-Disposition": f'attachment; filename="ARCHi-item-{listing["recipeID"]}.json"'})
                return Response(200, {"listing": listing})
            if account is None:
                account = self._authenticate(db, token, required=True)
            if path == "/v1/sessions/current" and method == "DELETE":
                db.execute("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(token.encode("ascii")).hexdigest(),))
                return Response(200, {"signedOut": True})
            request_hash = hashlib.sha256(json_bytes([method, path, body])).hexdigest()
            if idempotency_key:
                previous = db.execute("SELECT * FROM idempotency WHERE account_id=? AND key=?", (account["id"], idempotency_key)).fetchone()
                if previous:
                    if previous["request_hash"] != request_hash:
                        raise APIError(409, "idempotency_conflict", "This retry key was used with different input. Refresh before continuing.")
                    return Response(previous["status"], json.loads(previous["response_json"]))
                capacity(db.execute("SELECT count(*) FROM idempotency WHERE account_id=?", (account["id"],)).fetchone()[0] >= MAX_IDEMPOTENCY,
                         "retry records per account")
            response = self._private_route(db, method, path, account, body, query)
            if idempotency_key:
                db.execute("INSERT INTO idempotency VALUES (?,?,?,?,?)", (account["id"], idempotency_key, request_hash,
                           response.status, json_bytes(response.value).decode("utf-8")))
            return response
