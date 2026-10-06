import copy
import os
import sqlite3
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from marketplace.model import APIError, json_bytes
from marketplace.store import Store, SESSION_SECONDS
from marketplace.tests.fixtures import PASSWORD, draft


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="archi-marketplace-test-")
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "synthetic.sqlite3"
        self.now = [1_790_000_000.0]
        self.store = Store(self.path, clock=lambda: self.now[0])
        self.owner, self.token = self.account("synthetic_owner")

    def account(self, handle):
        account = self.store.dispatch("POST", "/v1/accounts", body={"handle": handle,
                                      "displayName": handle.replace("_", " ").title(), "password": PASSWORD}).value["account"]
        session = self.store.dispatch("POST", "/v1/sessions", body={"handle": handle, "password": PASSWORD})
        return account, session.value["token"]

    def call(self, method, path, body=None, token=None, **kwargs):
        return self.store.dispatch(method, path, body=body, token=self.token if token is None else token, **kwargs)

    def listing(self, title="Synthetic Staff"):
        return self.call("POST", "/v1/listings", draft(title)).value["listing"]

    def publish(self, listing):
        return self.call("POST", f'/v1/listings/{listing["id"]}/publish',
                         {"expectedVersion": listing["version"]}).value["listing"]

    def acquisition(self, listing, token=None, **kwargs):
        return self.call("POST", "/v1/inventory", {"listingID": listing["id"], "version": listing["version"],
                          "recipeID": listing["recipeID"]}, token=token, **kwargs)

    def assert_error(self, code, method, path, **kwargs):
        with self.assertRaises(APIError) as caught:
            self.store.dispatch(method, path, **kwargs)
        self.assertEqual(caught.exception.code, code)
        return caught.exception

    def test_empty_catalog_no_profile_or_fixture_seed(self):
        self.assertEqual(self.store.dispatch("GET", "/v1/catalog").value, {"items": [], "total": 0, "limit": 40, "offset": 0})
        self.assertEqual(self.call("GET", "/v1/inventory").value["total"], 0)
        self.assertEqual(self.call("GET", "/v1/me/listings").value["total"], 0)

    def test_restart_retains_account_session_listing_and_inventory(self):
        published = self.publish(self.listing())
        acquired = self.acquisition(published).value["entry"]
        self.store = Store(self.path, clock=lambda: self.now[0])
        self.assertEqual(self.call("GET", "/v1/me").value["account"], self.owner)
        self.assertEqual(self.call("GET", "/v1/me/listings").value["items"], [published])
        self.assertEqual(self.call("GET", "/v1/inventory").value["items"], [acquired])

    def test_password_and_session_secrets_are_hashed_not_stored_raw(self):
        with sqlite3.connect(self.path) as db:
            row = db.execute("SELECT password_salt,password_hash FROM accounts").fetchone()
            token_hash = db.execute("SELECT token_hash FROM sessions").fetchone()[0]
        self.assertEqual(len(row[0]), 32)
        self.assertEqual(len(row[1]), 32)
        self.assertEqual(len(token_hash), 64)
        self.assertNotIn(self.token.encode(), self.path.read_bytes())
        self.assertNotIn(PASSWORD.encode(), self.path.read_bytes())
        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)

    def test_session_failure_expiry_and_logout(self):
        self.assert_error("unauthorized", "POST", "/v1/sessions", body={"handle": "synthetic_owner", "password": "wrong but long enough"})
        self.assert_error("unauthorized", "POST", "/v1/sessions", body={"handle": "synthetic_missing", "password": PASSWORD})
        self.assertEqual(self.call("DELETE", "/v1/sessions/current").value, {"signedOut": True})
        self.assert_error("unauthorized", "GET", "/v1/me", token=self.token)
        fresh = self.store.dispatch("POST", "/v1/sessions", body={"handle": "synthetic_owner", "password": PASSWORD}).value["token"]
        self.now[0] += SESSION_SECONDS
        self.assert_error("unauthorized", "GET", "/v1/me", token=fresh)

    def test_handles_are_unique_and_display_names_do_not_grant_identity(self):
        self.assert_error("handle_taken", "POST", "/v1/accounts", body={"handle": "synthetic_owner", "displayName": "Else", "password": PASSWORD})
        for handle in ("a", "HasUppercase", "spaces here", "1starts_digit", "_prefix"):
            with self.subTest(handle=handle):
                self.assert_error("validation_failed", "POST", "/v1/accounts", body={"handle": handle, "displayName": "Test", "password": PASSWORD})
        listing = self.listing()
        self.assertEqual(listing["publisher"]["id"], self.owner["id"])
        self.assertEqual(listing["recipe"]["creator"], "Synthetic Artist")
        self.assertNotIn("isVerified", listing["publisher"])
        self.assertNotIn("isRegistered", listing)

    def test_other_accounts_cannot_read_drafts_or_mutate_any_owned_listing(self):
        _, stranger = self.account("synthetic_stranger")
        listing = self.listing()
        path = f'/v1/listings/{listing["id"]}'
        for method, suffix, body in (("GET", "", None), ("GET", "/versions", None),
                                     ("GET", "/versions/1/package", None),
                                     ("PUT", "", dict(draft(), expectedVersion=1)),
                                     ("POST", "/publish", {"expectedVersion": 1}),
                                     ("POST", "/archive", {"expectedVersion": 1})):
            with self.subTest(method=method, suffix=suffix):
                self.assert_error("not_found", method, path + suffix, body=body, token=stranger)
        self.assert_error("not_found", "GET", path)
        self.assertEqual(self.call("GET", "/v1/me/listings", token=stranger).value["total"], 0)

    def test_full_version_lifecycle_preserves_public_version_then_hides_archive(self):
        listing = self.listing()
        self.assertEqual((listing["version"], listing["status"], listing["publishedVersion"]), (1, "draft", None))
        published = self.publish(listing)
        path = f'/v1/listings/{listing["id"]}'
        self.assertEqual(published["version"], 2)
        self.assertEqual(published["recipeID"], listing["recipeID"])
        edit = self.call("PUT", path, dict(draft("Changed Synthetic"), expectedVersion=2)).value["listing"]
        self.assertEqual((edit["version"], edit["publishedVersion"], edit["status"]), (3, 2, "draft"))
        self.assertEqual(self.store.dispatch("GET", "/v1/catalog").value["items"][0]["version"], 2)
        self.assertEqual(self.store.dispatch("GET", path).value["listing"]["version"], 2)
        self.assertEqual(self.call("GET", path).value["listing"]["version"], 3)
        latest = self.publish(edit)
        self.assertEqual(latest["version"], 4)
        self.assertEqual(self.store.dispatch("GET", "/v1/catalog").value["items"], [latest])
        archived = self.call("POST", path + "/archive", {"expectedVersion": 4}).value["listing"]
        self.assertEqual((archived["version"], archived["status"], archived["publishedVersion"]), (5, "archived", None))
        self.assertEqual(self.store.dispatch("GET", "/v1/catalog").value["items"], [])
        self.assert_error("not_found", "GET", path)
        self.assert_error("state_conflict", "POST", path + "/publish", body={"expectedVersion": 5}, token=self.token)
        history = self.call("GET", path + "/versions").value["items"]
        self.assertEqual([v["version"] for v in history], [5, 4, 3, 2, 1])
        self.assertEqual(history[-1]["recipe"], listing["recipe"])
        redraft = self.call("PUT", path, dict(draft("Revised after archive"), expectedVersion=5)).value["listing"]
        self.assertEqual(self.publish(redraft)["version"], 7)

    def test_stale_version_and_invalid_mutations_do_not_write(self):
        published = self.publish(self.listing())
        path = f'/v1/listings/{published["id"]}'
        self.assert_error("version_conflict", "PUT", path, body=dict(draft("Lost update"), expectedVersion=1), token=self.token)
        invalid = dict(draft("Invalid update"), expectedVersion=2)
        invalid["provenance"]["rightsConfirmed"] = False
        self.assert_error("validation_failed", "PUT", path, body=invalid, token=self.token)
        self.assertEqual(self.call("GET", path).value["listing"], published)
        self.assertEqual(self.call("GET", path + "/versions").value["total"], 2)

    def test_recipe_download_is_closed_and_retained_for_acquirer_after_archive(self):
        _, collector = self.account("synthetic_collector")
        published = self.publish(self.listing())
        acquired = self.acquisition(published, token=collector).value["entry"]
        path = f'/v1/listings/{published["id"]}/versions/2/package'
        public = self.store.dispatch("GET", path)
        self.assertEqual(public.value, published["recipe"])
        self.assertLessEqual(len(json_bytes(public.value)), 4096)
        self.assertEqual(public.headers["X-ARCHi-Recipe-ID"], published["recipeID"])
        self.call("POST", f'/v1/listings/{published["id"]}/archive', {"expectedVersion": 2})
        self.assert_error("not_found", "GET", path)
        self.assertEqual(self.call("GET", path, token=collector).value, public.value)
        self.assertEqual(self.call("GET", "/v1/inventory", token=collector).value["items"], [acquired])
        self.assert_error("listing_changed", "POST", "/v1/inventory", body={"listingID": published["id"],
                         "version": 2, "recipeID": published["recipeID"]}, token=self.token)

    def test_acquisition_deduplicates_across_listing_revisions_and_publishers(self):
        _, collector = self.account("synthetic_collector")
        first, second = self.publish(self.listing()), self.publish(self.listing())
        one = self.acquisition(first, token=collector)
        two = self.acquisition(second, token=collector)
        self.assertEqual(one.status, 201)
        self.assertEqual(two.status, 200)
        self.assertFalse(one.value["alreadyAcquired"])
        self.assertTrue(two.value["alreadyAcquired"])
        self.assertEqual(one.value["entry"], two.value["entry"])
        self.assertEqual(self.call("GET", "/v1/inventory", token=collector).value["total"], 1)
        self.assertEqual(self.call("GET", "/v1/inventory").value["total"], 0)

    def test_stale_catalog_acquisition_requires_review_of_exact_public_digest(self):
        published = self.publish(self.listing())
        for version, digest in ((1, published["recipeID"]), (2, "0" * 64)):
            self.assert_error("listing_changed", "POST", "/v1/inventory", body={"listingID": published["id"],
                              "version": version, "recipeID": digest}, token=self.token)
        self.assertEqual(self.call("GET", "/v1/inventory").value["total"], 0)

    def test_idempotent_retry_returns_committed_response_without_extra_version(self):
        key = str(uuid.uuid4())
        original = self.call("POST", "/v1/listings", draft(), idempotency_key=key)
        self.store = Store(self.path, clock=lambda: self.now[0])
        retry = self.call("POST", "/v1/listings", draft(), idempotency_key=key.upper())
        self.assertEqual(retry.value, original.value)
        self.assertEqual(self.call("GET", "/v1/me/listings").value["total"], 1)
        self.assert_error("idempotency_conflict", "POST", "/v1/listings", body=draft("Changed request"),
                          token=self.token, idempotency_key=key)
        listing = original.value["listing"]
        publish_key = str(uuid.uuid4())
        path = f'/v1/listings/{listing["id"]}/publish'
        published = self.call("POST", path, {"expectedVersion": 1}, idempotency_key=publish_key)
        self.assertEqual(self.call("POST", path, {"expectedVersion": 1}, idempotency_key=publish_key).value, published.value)
        self.assertEqual(self.call("GET", f'/v1/listings/{listing["id"]}/versions').value["total"], 2)

    def test_same_retry_key_is_scoped_to_account(self):
        _, other = self.account("synthetic_other")
        key = str(uuid.uuid4())
        first = self.call("POST", "/v1/listings", draft(), idempotency_key=key)
        second = self.call("POST", "/v1/listings", draft(), token=other, idempotency_key=key)
        self.assertNotEqual(first.value["listing"]["id"], second.value["listing"]["id"])

    def test_concurrent_duplicate_acquisition_has_one_persistent_entry(self):
        published = self.publish(self.listing())
        with ThreadPoolExecutor(max_workers=8) as executor:
            results = list(executor.map(lambda _: self.acquisition(published), range(8)))
        self.assertEqual(sum(r.status == 201 for r in results), 1)
        self.assertEqual(len({r.value["entry"]["id"] for r in results}), 1)
        self.assertEqual(self.call("GET", "/v1/inventory").value["total"], 1)

    def test_search_is_casefolded_literal_and_paginated(self):
        titles = ["Synthetic Straße", "100% Glow", "Under_score"]
        for title in titles:
            self.publish(self.listing(title))
        for term, count in (("STRASSE", 1), ("%", 1), ("_", 3), ("100%", 1), ("' OR 1=1--", 0),
                            ("archi-item-design/v1", 0), ("synthetic_owner", 3)):
            with self.subTest(term=term):
                page = self.store.dispatch("GET", "/v1/catalog", query={"q": term}).value
                self.assertEqual(page["total"], count)
        first = self.call("GET", "/v1/me/listings", query={"limit": "1", "offset": "0"}).value
        next_page = self.call("GET", "/v1/me/listings", query={"limit": "1", "offset": "1"}).value
        self.assertEqual(first["total"], 3)
        self.assertNotEqual(first["items"][0]["id"], next_page["items"][0]["id"])
        for query in ({"limit": "101"}, {"offset": "10001"}, {"offset": "-1"}, {"unknown": "x"}):
            with self.assertRaises(APIError):
                self.store.dispatch("GET", "/v1/catalog", query=query)

    def test_capacity_limit_rolls_back_instead_of_partially_saving(self):
        with patch("marketplace.store.MAX_LISTINGS", 1):
            self.listing()
            self.assert_error("capacity_reached", "POST", "/v1/listings", body=draft("Overflow"), token=self.token)
            self.assertEqual(self.call("GET", "/v1/me/listings").value["total"], 1)

    def test_corrupt_stored_recipe_is_not_downloaded_or_added(self):
        published = self.publish(self.listing())
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE versions SET recipe_id=? WHERE listing_id=? AND version=2", ("0" * 64, published["id"]))
        self.assert_error("storage_unavailable", "GET", f'/v1/listings/{published["id"]}/versions/2/package')
        self.assertEqual(self.call("GET", "/v1/inventory").value["total"], 0)

    def test_refuses_symlink_permissive_or_unrelated_database(self):
        link = self.path.with_name("linked.sqlite3")
        link.symlink_to(self.path)
        with self.assertRaises(OSError):
            Store(link)
        mode_path = self.path.with_name("permissive.sqlite3")
        mode_path.touch(mode=0o644)
        mode_path.chmod(0o644)
        with self.assertRaises(ValueError):
            Store(mode_path)
        unrelated = self.path.with_name("unrelated.sqlite3")
        unrelated.touch(mode=0o600)
        with sqlite3.connect(unrelated) as db:
            db.execute("CREATE TABLE personal_data(value TEXT)")
        before = unrelated.read_bytes()
        with self.assertRaises(ValueError):
            Store(unrelated)
        self.assertEqual(unrelated.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
