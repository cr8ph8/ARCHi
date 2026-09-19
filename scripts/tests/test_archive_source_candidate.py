"""Archive read-back, exact allowlist scope and preservation requirements."""
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "script"))
import archive_source_candidate as packaging


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.root = self.folder / "source-fixture"
        self.root.mkdir()
        source = self.root / "source.py"
        source.write_text("print('fixture')\n")
        source.chmod(0o755)
        self.data = source.read_bytes()
        self.manifest = f"{packaging.preflight.sha(self.data)}  source.py\n".encode()
        (self.root / "SOURCE_SHA256SUMS").write_bytes(self.manifest)
        self.scope = patch.object(packaging.preflight, "collect", return_value=(["source.py"], []))
        self.scope.start()
        self.addCleanup(self.scope.stop)

    def archive(self, name="one"):
        return packaging.archive(self.root, self.folder / (name + ".tar.gz"), self.folder / (name + ".json"))

    def test_roundtrip_is_reproducible_and_contains_only_allowlisted_source(self):
        (self.root / "private.sqlite3").write_bytes(b"private data must not be archived")
        first, second = self.archive("one"), self.archive("two")
        self.assertEqual(first["archiveSha256"], second["archiveSha256"])
        self.assertEqual(first["members"], 2)
        self.assertFalse(first["publicationAuthorized"])
        with tarfile.open(self.folder / "one.tar.gz") as tar:
            self.assertEqual(tar.getnames(), ["source-fixture/SOURCE_SHA256SUMS", "source-fixture/source.py"])
            self.assertEqual(tar.getmember("source-fixture/source.py").mode, 0o755)
            self.assertEqual(tar.extractfile("source-fixture/source.py").read(), self.data)

    def test_stale_manifest_prevents_any_archive(self):
        (self.root / "source.py").write_text("changed source\n")
        with self.assertRaises(ValueError):
            self.archive()
        self.assertFalse((self.folder / "one.tar.gz").exists())

    def test_private_metadata_prevents_archive_even_if_manifest_matches(self):
        data = b"/" + b"Users/synthetic/private-source\n"
        (self.root / "source.py").write_bytes(data)
        (self.root / "SOURCE_SHA256SUMS").write_text(f"{packaging.preflight.sha(data)}  source.py\n")
        with self.assertRaises(ValueError):
            self.archive()
        self.assertFalse((self.folder / "one.tar.gz").exists())

    def test_existing_outputs_and_inside_candidate_paths_are_refused(self):
        self.archive()
        before = (self.folder / "one.tar.gz").read_bytes()
        with self.assertRaises(ValueError):
            self.archive()
        self.assertEqual((self.folder / "one.tar.gz").read_bytes(), before)
        with self.assertRaises(ValueError):
            packaging.archive(self.root, self.root / "inside.tar.gz", self.folder / "new.json")

    def test_linked_source_and_manifest_are_refused(self):
        source = self.root / "source.py"
        target = self.folder / "outside.py"
        target.write_bytes(self.data)
        source.unlink()
        source.symlink_to(target)
        with self.assertRaises(ValueError):
            self.archive()
        source.unlink()
        source.write_bytes(self.data)
        manifest = self.root / "SOURCE_SHA256SUMS"
        manifest.unlink()
        target_manifest = self.folder / "other-manifest"
        target_manifest.write_bytes(self.manifest)
        manifest.symlink_to(target_manifest)
        with self.assertRaises(ValueError):
            self.archive()

    def test_changed_source_during_packaging_does_not_gain_a_pass_receipt(self):
        original = packaging.snapshot
        calls = []
        def changed(root):
            result = original(root)
            calls.append(root)
            if len(calls) == 1:
                (root / "source.py").write_bytes(b"changed after snapshot\n")
            return result
        with patch.object(packaging, "snapshot", side_effect=changed), self.assertRaises(ValueError):
            self.archive()
        self.assertFalse((self.folder / "one.json").exists())


if __name__ == "__main__":
    unittest.main()
