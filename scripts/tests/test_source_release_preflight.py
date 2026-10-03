"""Release gates: exclusion/symlink safety, complete rig inventory and receipts."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zlib

SPEC = importlib.util.spec_from_file_location("source_preflight", Path(__file__).resolve().parents[2] / "script/source_release_preflight.py")
preflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preflight)


def chunk(kind, payload):
    return len(payload).to_bytes(4, "big") + kind + payload + (zlib.crc32(kind + payload) & 0xffffffff).to_bytes(4, "big")


class SourceReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def put(self, path, value=b"source\n"):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(value)
        return file

    def test_explicit_roots_include_fbx_and_its_meta_but_no_caches_or_authored_blends(self):
        self.put("unity/ARCHi/Assets/Resources/Proto/body.fbx")
        self.put("unity/ARCHi/Assets/Resources/Proto/body.fbx.meta")
        self.put("unity/ARCHi/Assets/Resources/Proto/provenance.json", b"{}")
        self.put("unity/ARCHi/Assets/Resources/Proto/provenance.json.meta")
        self.put("unity/ARCHi/Assets/ArtSources/original.blend")
        self.put("unity/ARCHi/Library/private.txt")
        self.put("output/private.json")
        scopes = {"unity/ARCHi/Assets": preflight.SCOPES["unity/ARCHi/Assets"]}
        paths, blockers = preflight.collect(self.root, set(), scopes)
        self.assertEqual(len(paths), 4)
        self.assertIn("unity/ARCHi/Assets/Resources/Proto/body.fbx", paths)
        self.assertEqual(blockers, [])

    def test_missing_unity_meta_blocks_reproducibility(self):
        self.put("unity/ARCHi/Assets/body.fbx")
        paths, blockers = preflight.collect(self.root, set(), {"unity/ARCHi/Assets": {".fbx", ".meta"}})
        self.assertEqual(paths, ["unity/ARCHi/Assets/body.fbx"])
        self.assertEqual(blockers, [{"code": "UNITY_META_MISSING", "path": "unity/ARCHi/Assets/body.fbx.meta"}])

    def test_creator_service_exports_code_docs_and_tests_without_local_database_or_cache(self):
        self.put("marketplace/__main__.py")
        self.put("marketplace/API.md")
        self.put("marketplace/.gitignore")
        self.put("marketplace/tests/test_store.py")
        self.put("marketplace/data/development.sqlite3", b"private local database")
        self.put("marketplace/data/export.py", b"private local content disguised as source")
        self.put("marketplace/__pycache__/store.cpython-311.pyc")
        paths, blockers = preflight.collect(self.root, {"marketplace/.gitignore"},
                                             {"marketplace": preflight.SCOPES["marketplace"]})
        self.assertEqual(paths, ["marketplace/.gitignore", "marketplace/API.md", "marketplace/__main__.py",
                                 "marketplace/tests/test_store.py"])
        self.assertEqual(blockers, [])

    def test_misplaced_sqlite_or_journal_is_never_exported_and_blocks_scope_review(self):
        for name in ("accounts.sqlite3", "accounts.sqlite3-wal", "accounts.sqlite3-shm", "accounts.sqlite3-journal"):
            self.put("marketplace/" + name)
        paths, blockers = preflight.collect(self.root, set(), {"marketplace": preflight.SCOPES["marketplace"]})
        self.assertEqual(paths, [])
        self.assertEqual(len(blockers), 4)
        self.assertTrue(all(row["code"] == "UNREVIEWED_FILE_KIND" for row in blockers))

    def test_unrecognized_source_kind_is_a_blocker_not_silent_omission(self):
        self.put("src/main.ts")
        self.put("src/runtime.wasm")
        paths, blockers = preflight.collect(self.root, set(), {"src": {".ts"}})
        self.assertEqual(paths, ["src/main.ts"])
        self.assertEqual(blockers, [{"code": "UNREVIEWED_FILE_KIND", "path": "src/runtime.wasm"}])

    def test_typescript_json_fixture_must_be_explicitly_in_reviewed_inventory(self):
        self.put("arc/test/portable.test.ts", b'import fixture from "../fixtures/portable/fraction.json";\n')
        fixture = "arc/fixtures/portable/fraction.json"
        self.put(fixture, b'{"synthetic":true}')
        paths, blockers = preflight.collect(self.root, set(), {"arc/test": {".ts"}})
        self.assertNotIn(fixture, paths)
        self.assertEqual(blockers, [{"code": "SOURCE_FIXTURE_DEPENDENCY_MISSING",
                                     "path": "arc/test/portable.test.ts", "dependency": fixture}])
        _, blockers = preflight.collect(self.root, {fixture}, {"arc/test": {".ts"}})
        self.assertEqual(blockers, [])

    def test_native_arc_fixture_dependency_is_checked_without_adding_arbitrary_json(self):
        source = "desktop/Tests/ARCHiDesktopTests/ARCCapabilitiesTests.swift"
        fixture = "arc/fixtures/portable/fraction.json"
        self.put(source, b'let input = root.appendingPathComponent("arc/fixtures/portable/fraction.json")\n')
        self.put(fixture, b'{"synthetic":true}')
        self.put("arc/fixtures/private-notes.json", b'private excluded fixture notes')
        paths, blockers = preflight.collect(self.root, {source}, {})
        self.assertEqual(paths, [source])
        self.assertEqual(blockers, [{"code": "SOURCE_FIXTURE_DEPENDENCY_MISSING",
                                     "path": source, "dependency": fixture}])
        paths, blockers = preflight.collect(self.root, {source, fixture}, {})
        self.assertEqual(blockers, [])
        self.assertNotIn("arc/fixtures/private-notes.json", paths)

    def replay_fixture(self):
        source = Path(__file__).resolve().parents[2]
        manifest = "scripts/arc-replay-pins.json"
        pins = json.loads((source / manifest).read_bytes())
        names = preflight.ARC_REPLAY_FILES | set(pins["files"])
        for name in names:
            self.put(name, (source / name).read_bytes())
        return manifest, pins, names

    def test_replay_source_exports_with_its_exact_pinned_closure_and_no_local_runs(self):
        manifest, pins, names = self.replay_fixture()
        self.put("scripts/private-notes.mjs", b"private notes")
        self.put("output/replay/manifest.json", b"local runtime receipt")
        paths, blockers = preflight.collect(self.root, names, {})
        self.assertEqual(blockers, [])
        self.assertEqual(set(paths), names)
        self.assertTrue(preflight.ARC_REPLAY_FILES <= preflight.EXACT)
        self.assertEqual(json.loads((self.root / manifest).read_bytes()), pins)
        self.assertNotIn("scripts/private-notes.mjs", paths)
        self.assertNotIn("output/replay/manifest.json", paths)

    def test_missing_replay_worker_blocks_export_before_execution(self):
        manifest, _, names = self.replay_fixture()
        worker = "scripts/arc-replay-worker.mjs"
        (self.root / worker).unlink()
        paths, blockers = preflight.collect(self.root, names, {})
        self.assertNotIn(worker, paths)
        self.assertIn({"code": "SOURCE_REPLAY_DEPENDENCY_MISSING", "path": manifest, "dependency": worker}, blockers)

    def test_replay_pins_cannot_expand_source_scope_to_private_data(self):
        manifest, pins, names = self.replay_fixture()
        private = "output/private.json"
        data = b"do not export or read private fixture"
        self.put(private, data)
        pins["files"][private] = "sha256:" + preflight.sha(data)
        self.put(manifest, preflight.json_bytes(pins))
        paths, blockers = preflight.collect(self.root, names, {})
        self.assertNotIn(private, paths)
        self.assertIn({"code": "SOURCE_REPLAY_DEPENDENCY_MISSING", "path": manifest, "dependency": private}, blockers)
        self.assertNotIn(data.decode(), json.dumps(blockers))

    def test_replay_invalid_path_is_rejected_without_exposing_it(self):
        manifest, pins, names = self.replay_fixture()
        pins["files"]["../outside/private.json"] = "sha256:" + "0" * 64
        self.put(manifest, preflight.json_bytes(pins))
        _, blockers = preflight.collect(self.root, names, {})
        self.assertIn({"code": "SOURCE_REPLAY_PINS_INVALID", "path": manifest}, blockers)
        self.assertNotIn("outside", json.dumps(blockers))

    def test_replay_checker_mutation_blocks_the_old_receipt_without_repinning(self):
        manifest, _, names = self.replay_fixture()
        pins_before = (self.root / manifest).read_bytes()
        worker = "scripts/arc-replay-worker.mjs"
        self.put(worker, (self.root / worker).read_bytes() + b"\n// altered checker\n")
        _, blockers = preflight.collect(self.root, names, {})
        self.assertIn({"code": "SOURCE_REPLAY_PIN_MISMATCH", "path": worker}, blockers)
        self.assertEqual((self.root / manifest).read_bytes(), pins_before)

    def test_symlinked_files_and_directories_are_never_read(self):
        outside = self.put("outside/private.txt")
        (self.root / "src").mkdir()
        (self.root / "src/link.ts").symlink_to(outside)
        (self.root / "src/nested").symlink_to(outside.parent, target_is_directory=True)
        paths, blockers = preflight.collect(self.root, set(), {"src": {".ts"}})
        self.assertEqual(paths, [])
        self.assertEqual(len(blockers), 2)
        self.assertTrue(all(row["code"] == "SOURCE_SYMLINK" for row in blockers))

    def test_intermediate_symlink_in_exact_path_is_rejected(self):
        self.put("outside/main.ts")
        (self.root / "src").symlink_to(self.root / "outside", target_is_directory=True)
        paths, blockers = preflight.collect(self.root, {"src/main.ts"}, {})
        self.assertEqual(paths, [])
        self.assertEqual(blockers[0]["code"], "SOURCE_SYMLINK")

    def test_scan_redacts_credentials_and_paths_even_in_binary(self):
        token = b"ghp_" + b"a" * 36
        home = b"/" + b"Users/fixture/"
        findings = preflight.scan("model.fbx", b"\x00" + token + b"\x00" + home + b"\x00")
        encoded = json.dumps(findings).encode()
        self.assertEqual({x["code"] for x in findings}, {"github-token", "private-home-path"})
        self.assertNotIn(token, encoded)
        self.assertNotIn(home, encoded)

    def test_png_all_text_metadata_requires_review_and_bad_crc_fails(self):
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"tEXt", b"File\0local-source") + chunk(b"IEND", b"")
        self.assertEqual(preflight.scan("body.png", png)[0]["code"], "png-text-metadata")
        corrupt = png[:-1] + bytes([png[-1] ^ 1])
        self.assertIn("invalid-png", [row["code"] for row in preflight.scan("body.png", corrupt)])

    def test_output_never_overwrites_authored_file_or_link(self):
        authored = self.put("report.json", b"preserve")
        with self.assertRaises(FileExistsError):
            preflight.write_new(authored, b"replacement")
        link = self.root / "link.json"
        link.symlink_to(authored)
        with self.assertRaises(FileExistsError):
            preflight.write_new(link, b"replacement")
        self.assertEqual(authored.read_bytes(), b"preserve")

    def review(self, digest, assets=()):
        evidence = self.put("check.log", b"actual fixture evidence")
        return {"sourceInventoryDigest": digest, "publicationScopeReviewed": True,
                "assetRights": [{**row, "status": "approved", "license": "MIT", "authority": "fixture authority"} for row in assets],
                "checks": [{"name": name, "status": "passed", "exitCode": 0, "sourceInventoryDigest": digest,
                            "command": "fixture command", "limitations": "fixture only", "evidencePath": str(evidence),
                            "evidenceSha256": preflight.sha(evidence.read_bytes())} for name in preflight.CHECK_NAMES]}

    def test_review_requires_current_digest_exact_asset_rights_and_real_receipt_bytes(self):
        asset = {"path": "body.fbx", "sha256": "b" * 64}
        review = self.review("a" * 64, [asset])
        self.assertEqual(preflight.validate_review(review, "a" * 64, [asset], self.root), [])
        review["assetRights"][0]["sha256"] = "c" * 64
        self.put("check.log", b"changed evidence")
        codes = {row["code"] for row in preflight.validate_review(review, "d" * 64, [asset], self.root)}
        self.assertIn("ASSET_REDISTRIBUTION_UNREVIEWED", codes)
        self.assertIn("REVIEW_SOURCE_DIGEST_MISMATCH", codes)
        self.assertIn("CHECK_UNQUALIFIED", codes)
        codes = {row["code"] for row in preflight.validate_review(review, "a" * 64, [asset], self.root)}
        self.assertIn("CHECK_EVIDENCE_MISMATCH", codes)

    def test_old_release_checks_do_not_qualify_new_creator_service_or_native_account_flow(self):
        review = self.review("a" * 64)
        new_gates = {"creator-marketplace-service", "native-creator-marketplace-acceptance"}
        self.assertTrue(new_gates <= preflight.CHECK_NAMES)
        review["checks"] = [row for row in review["checks"] if row["name"] not in new_gates]
        blockers = preflight.validate_review(review, "a" * 64, [], self.root)
        self.assertEqual({row["check"] for row in blockers}, new_gates)
        self.assertTrue(all(row["code"] == "CHECK_UNQUALIFIED" for row in blockers))

    def test_full_fixture_blocks_until_clean_tracked_manifest_and_review_then_passes(self):
        self.put("src/main.ts")
        state = {"isRootRepository": True, "head": "a" * 40, "branch": "fixture", "clean": True, "statusRecordCount": 0, "tracked": {"src/main.ts", "SOURCE_SHA256SUMS"}}
        with patch.object(preflight, "git_state", side_effect=lambda _: dict(state)):
            first = preflight.audit(self.root, exact=set(), scopes={"src": {".ts"}})
            self.assertEqual(first["status"], "BLOCKED")
            self.put("SOURCE_SHA256SUMS", first["checksums"].encode())
            review = self.review(first["sourceInventoryDigest"])
            second = preflight.audit(self.root, review=review, exact=set(), scopes={"src": {".ts"}})
            self.assertEqual(second["status"], "PREFLIGHT_PASS")
            self.assertFalse(second["publicationAuthorized"])
            self.assertFalse(second["notarizedAppReady"])
            state["clean"] = False
            third = preflight.audit(self.root, review=review, exact=set(), scopes={"src": {".ts"}})
            self.assertEqual(third["status"], "BLOCKED")
            self.put("src/main.ts", b"changed\n")
            fourth = preflight.audit(self.root, review=review, exact=set(), scopes={"src": {".ts"}})
            self.assertIn("SOURCE_CHECKSUMS_STALE", [row["code"] for row in fourth["blockers"]])

    def test_tracked_private_paths_block_without_opening_contents(self):
        self.put("src/main.ts")
        state = {"isRootRepository": True, "head": "a" * 40, "branch": "fixture", "clean": True, "statusRecordCount": 0, "tracked": {"src/main.ts", "docs/research/private-archive/chat.json"}}
        with patch.object(preflight, "git_state", return_value=state):
            report = preflight.audit(self.root, exact=set(), scopes={"src": {".ts"}})
        self.assertIn("TRACKED_FILES_OUTSIDE_ALLOWLIST", [row["code"] for row in report["blockers"]])
        self.assertEqual(report["sourceFileCount"], 1)

    def test_scanner_source_does_not_match_its_own_patterns(self):
        self.assertEqual(preflight.scan("script/source_release_preflight.py", Path(preflight.__file__).read_bytes()), [])


if __name__ == "__main__":
    unittest.main()
