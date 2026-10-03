"""Read-only source/publication parity and exact review-policy boundaries."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[2] / "script/check_source_parity.py"


class SourceParityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source = self.root / "source"
        self.publication = self.root / "publication"
        for root in (self.source, self.publication):
            root.mkdir()
            self.git(root, "init", "-q")
        self.path = "desktop/Sources/ARCHiDesktop/Companion.swift"
        self.put_both(self.path)

    @staticmethod
    def git(root, *args):
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                              check=True, env=env)

    @staticmethod
    def put(root, relative, value=b"original\n"):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)
        return path

    def put_both(self, relative, value=b"original\n"):
        for root in (self.source, self.publication):
            self.put(root, relative, value)

    def run_check(self, policy=None, source=None, publication=None):
        command = [sys.executable, str(CHECKER), "--source", str(source or self.source),
                   "--publication", str(publication or self.publication)]
        if policy is not None:
            command += ["--policy", str(policy)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.stderr, "")
        self.assertNotIn(str(self.root), result.stdout)
        return result.returncode, json.loads(result.stdout)

    def policy(self, entries):
        return self.put(self.root, "policy.json", json.dumps(
            {"schemaVersion": 1, "reviewedDifferences": entries}).encode())

    def entry(self, source=b"original\n", publication=b"sanitized\n", path=None):
        return {"path": path or self.path, "sourceSHA256": hashlib.sha256(source).hexdigest(),
                "publicationSHA256": hashlib.sha256(publication).hexdigest(),
                "reason": "Reviewed metadata-sanitized asset hash literal."}

    @staticmethod
    def snapshot(root):
        # Content, names and mtimes include Git metadata. Reading may change atime.
        return {path.relative_to(root).as_posix(): (path.read_bytes(), path.stat().st_mtime_ns)
                for path in root.rglob("*") if path.is_file() and not path.is_symlink()}

    def test_exact_match_ignores_unselected_content_and_does_not_mutate(self):
        for relative in ("desktop/Tests/ARCHiDesktopTests/Test.swift", "src/main.ts", "src/main.css",
                         "unity/ARCHi/Assets/ARCHi/Nested/Actor.cs",
                         "unity/ARCHi/Assets/ARCHi/Shaders/Body.shader"):
            self.put_both(relative)
        ignored = ("src/nested/private.ts", "desktop/Sources/ARCHiDesktop/Resources/private.swift",
                   "desktop/Profiles/private.json", "unity/ARCHi/Library/Generated.cs",
                   "unity/ARCHi/Assets/ARCHi/body.png", "unity/ARCHi/Assets/ARCHi/build/Generated.cs",
                   "scripts/local-unpublished.py", "private/secret.py")
        for relative in ignored:
            self.put(self.source, relative, b"do not compare")
            self.put(self.publication, relative, b"different excluded contents")
        before = self.snapshot(self.root)
        code, report = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(report["counts"]["matched"], 6)
        self.assertEqual(report["differences"], [])
        self.assertEqual(before, self.snapshot(self.root))

    def test_byte_drift_new_source_and_publication_only_files_fail(self):
        self.put(self.publication, self.path, b"changed\n")
        self.put(self.source, "src/new.ts")
        self.put(self.publication, "src/published-only.css")
        code, report = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual({(item["code"], item["path"], item.get("side"))
                          for item in report["differences"]}, {
            ("CHANGED", self.path, None), ("MISSING", "src/new.ts", "publication"),
            ("MISSING", "src/published-only.css", "source")})

    def test_only_published_tracked_ancillary_code_is_selected(self):
        tracked = ("script/check.py", "scripts/sub/tool.mjs", "scripts/run.sh",
                   "unity/ARCHi/Packages/example/Editor/Tool.cs")
        for relative in tracked:
            self.put_both(relative)
            self.git(self.publication, "add", "--", relative)
        self.put(self.publication, tracked[0], b"drift")
        (self.source / tracked[1]).unlink()
        (self.publication / tracked[2]).unlink()
        for relative in ("scripts/config.json", "scripts/node_modules/private/tool.py", "outside/read.py"):
            self.put(self.publication, relative)
            self.git(self.publication, "add", "-f", "--", relative)
        code, report = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual(report["counts"]["selected"], 5)
        self.assertEqual({item["path"] for item in report["differences"]}, set(tracked[:3]))

    def test_file_and_recursive_directory_symlinks_are_rejected(self):
        outside = self.put(self.root, "outside.txt", b"private")
        (self.source / self.path).unlink()
        (self.source / self.path).symlink_to(outside)
        directory = self.publication / "unity/ARCHi/Assets/ARCHi"
        directory.mkdir(parents=True)
        (directory / "nested").symlink_to(self.root, target_is_directory=True)
        code, report = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual({(item["code"], item["path"]) for item in report["differences"]}, {
            ("SYMLINK", self.path), ("SYMLINK", "unity/ARCHi/Assets/ARCHi/nested")})

    def test_scope_and_tracked_file_symlink_ancestors_are_rejected(self):
        target = self.root / "outside"
        target.mkdir()
        self.put(target, "main.ts")
        (self.source / "src").symlink_to(target, target_is_directory=True)
        self.put(self.publication, "src/main.ts")
        self.put_both("scripts/sub/check.py")
        self.git(self.publication, "add", "scripts/sub/check.py")
        (self.publication / "scripts/sub/check.py").unlink()
        (self.publication / "scripts/sub").rmdir()
        (self.publication / "scripts/sub").symlink_to(target, target_is_directory=True)
        code, report = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual({(item["code"], item["path"]) for item in report["differences"]}, {
            ("SYMLINK", "src"), ("SYMLINK", "scripts/sub")})

    def test_root_symlink_ancestor_and_missing_root_are_input_errors(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        for source, expected in ((alias / "source", "SYMLINK_INPUT"),
                                 (self.root / "missing", "INPUT_UNAVAILABLE")):
            code, report = self.run_check(source=source)
            self.assertEqual(code, 2)
            self.assertEqual(report["errors"][0]["code"], expected)

    def test_tracked_symlink_mode_fails_even_if_working_file_was_replaced(self):
        relative = "scripts/link.py"
        self.put(self.source, relative)
        path = self.publication / relative
        path.parent.mkdir()
        path.symlink_to(self.source / relative)
        self.git(self.publication, "add", relative)
        path.unlink()
        path.write_bytes(b"original\n")
        code, report = self.run_check()
        self.assertEqual(code, 1)
        self.assertEqual(report["differences"], [{"code": "SYMLINK", "path": relative, "side": "publication"}])

    def test_only_exact_reviewed_unequal_hash_pair_is_admitted(self):
        self.put(self.publication, self.path, b"sanitized\n")
        policy = self.policy([self.entry()])
        before = self.snapshot(self.root)
        code, report = self.run_check(policy)
        self.assertEqual(code, 0)
        self.assertEqual(report["counts"]["reviewed"], 1)
        self.assertEqual(report["reviewedDifferences"], [self.entry()])
        self.assertEqual(before, self.snapshot(self.root))
        self.put(self.publication, self.path, b"sanitized\n ")
        code, report = self.run_check(policy)
        self.assertEqual(code, 1)
        self.assertEqual({item["code"] for item in report["differences"]}, {"CHANGED", "UNUSED_OR_STALE_POLICY"})

    def test_equal_unused_out_of_scope_and_missing_policy_entries_fail(self):
        for entry in (self.entry(), self.entry(path="private/not-selected.swift"),
                      self.entry(path="src/missing.ts")):
            with self.subTest(path=entry["path"]):
                code, report = self.run_check(self.policy([entry]))
                self.assertEqual(code, 1)
                self.assertEqual(report["differences"], [{"code": "UNUSED_OR_STALE_POLICY", "path": entry["path"]}])

    def test_duplicate_entries_directory_exclusions_and_invalid_policy_fail(self):
        policies = [self.policy([self.entry(), self.entry()]).read_bytes(),
                    b'{"schemaVersion":1,"reviewedDifferences":[],"exclude":["desktop"]}',
                    b'{"schemaVersion":1,"schemaVersion":1,"reviewedDifferences":[]}',
                    json.dumps({"schemaVersion": 1, "reviewedDifferences": [self.entry(path="../outside.py")]}).encode(),
                    b'{"schemaVersion":true,"reviewedDifferences":[]}']
        for raw in policies:
            with self.subTest(policy=raw):
                policy = self.put(self.root, "policy.json", raw)
                code, report = self.run_check(policy)
                self.assertEqual(code, 2)
                self.assertEqual(report["errors"], [{"code": "INVALID_POLICY", "input": "policy"}])

    def test_missing_publication_file_cannot_be_admitted_by_policy(self):
        (self.publication / self.path).unlink()
        code, report = self.run_check(self.policy([self.entry()]))
        self.assertEqual(code, 1)
        self.assertEqual({item["code"] for item in report["differences"]}, {"MISSING", "UNUSED_OR_STALE_POLICY"})

    def test_non_repository_publication_and_bad_arguments_return_json_input_error(self):
        empty = self.root / "not-a-repository"
        empty.mkdir()
        code, report = self.run_check(publication=empty)
        self.assertEqual(code, 2)
        self.assertEqual(report["errors"][0]["code"], "PUBLICATION_GIT_UNAVAILABLE")
        result = subprocess.run([sys.executable, str(CHECKER)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(json.loads(result.stdout)["errors"][0]["code"], "INVALID_ARGUMENTS")
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
