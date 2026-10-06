"""Display mapping qualification and non-destructive staging; no applications run."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / "script"
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("package_liminal_finish", SCRIPTS / "package_liminal_finish.py")
finish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finish)


class FinishPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="archi-finish-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "base"
        self.source.mkdir()
        self.base_bytes = json.dumps({"lod": {"ids": {"sha256": "b" * 64}}}).encode()
        (self.source / "manifest.json").write_bytes(self.base_bytes)
        self.finish = self.root / "finish-v11"
        self.finish.mkdir()
        self.annotations = bytearray(struct.pack("<3fI", 1, 0, 0, 0) * finish.COUNT)
        struct.pack_into("<3fI", self.annotations, 0, 1, 0, 0, 1)
        self.manifest = {**finish.DISPLAY_METADATA, "schemaVersion": 1, "revision": finish.REVISION,
                         "sourceManifestSHA256": hashlib.sha256(self.base_bytes).hexdigest(),
                         "lodSHA256": "b" * 64, "blenderSHA256": "c" * 64,
                         "pointCount": finish.COUNT, "stride": finish.STRIDE,
                         "annotations": {"file": "annotations.bin", "bytes": len(self.annotations)}}
        self.pin = patch.object(finish, "EXPECTED_MANIFEST_SHA256", "")
        self.pin.start()
        self.addCleanup(self.pin.stop)
        self.qualify_fixture()

    def qualify_fixture(self):
        """Synthetic trusted pin, only within this test process."""
        (self.finish / "annotations.bin").write_bytes(self.annotations)
        self.manifest["annotations"]["sha256"] = hashlib.sha256(self.annotations).hexdigest()
        data = json.dumps(self.manifest, sort_keys=True).encode()
        (self.finish / "manifest.json").write_bytes(data)
        finish.EXPECTED_MANIFEST_SHA256 = hashlib.sha256(data).hexdigest()

    def targets(self):
        native, unity = self.root / "native", self.root / "unity"
        for root in (native, unity):
            shutil.copytree(self.source, root / "LiminalV008")
        return native, unity

    def player(self):
        player = self.root / "Player.app"
        resources = player / "Contents/Resources/Data/StreamingAssets/LiminalV008"
        shutil.copytree(self.source, resources)
        shutil.copytree(self.finish, resources / "finish-v11")
        info = {"ARCHiLiminalPointAssetVersion": 6,
                "ARCHiLiminalPointFinishSHA256": finish.EXPECTED_MANIFEST_SHA256}
        (player / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        return player, info

    def test_exact_finish_copies_identically_and_preserves_authenticated_base(self):
        native, unity = self.targets()
        expected = finish.package_finish(self.finish, self.source, native, unity)
        for root in (native, unity):
            self.assertEqual((root / "LiminalV008/manifest.json").read_bytes(), self.base_bytes)
            for name in ("annotations.bin", "manifest.json"):
                self.assertEqual((root / "LiminalV008/finish-v11" / name).read_bytes(), (self.finish / name).read_bytes())
        self.assertEqual(expected, finish.package_finish(self.finish, self.source, native, unity))
        self.assertEqual((self.source / "manifest.json").read_bytes(), self.base_bytes)

    def test_export_cannot_qualify_itself_by_changing_manifest_or_annotation(self):
        path = self.finish / "manifest.json"
        original = path.read_bytes()
        path.write_bytes(original + b" ")
        with self.assertRaisesRegex(ValueError, "Unqualified finish"):
            finish.validate_finish(self.finish, self.source)
        path.write_bytes(original)
        with (self.finish / "annotations.bin").open("r+b") as stream:
            stream.write(b"xxxx")
        with self.assertRaisesRegex(ValueError, "annotation bytes changed"):
            finish.validate_finish(self.finish, self.source)

    def test_missing_release_pin_fails_closed(self):
        finish.EXPECTED_MANIFEST_SHA256 = "PENDING_EXPORT"
        with self.assertRaisesRegex(ValueError, "not been pinned"):
            finish.validate_finish(self.finish, self.source)

    def test_wrong_source_or_lod_is_rejected(self):
        for key in ("sourceManifestSHA256", "lodSHA256"):
            with self.subTest(key=key):
                original = self.manifest[key]
                self.manifest[key] = "d" * 64
                self.qualify_fixture()
                with self.assertRaises(ValueError):
                    finish.validate_finish(self.finish, self.source)
                self.manifest[key] = original

    def test_nonfinite_nonunit_bad_flags_or_combined_seed_flag_rejected(self):
        for record in ((float("nan"), 0, 0, 1), (.5, 0, 0, 0), (1, 0, 0, 16),
                       (.5, 0, 0, 1), (1, 0, 0, 3)):
            with self.subTest(record=record):
                struct.pack_into("<3fI", self.annotations, 0, *record)
                self.qualify_fixture()
                with self.assertRaises(ValueError):
                    finish.validate_finish(self.finish, self.source)

    def test_extra_files_and_symlinks_are_not_packaged(self):
        extra = self.finish / "extra.json"
        extra.write_text("{}")
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            finish.validate_finish(self.finish, self.source)
        extra.unlink()
        annotations = self.finish / "annotations.bin"
        annotations.rename(self.root / "outside.bin")
        annotations.symlink_to(self.root / "outside.bin")
        with self.assertRaisesRegex(ValueError, "regular file"):
            finish.validate_finish(self.finish, self.source)

    def test_player_requires_six_exact_digest_and_qualified_embedded_finish(self):
        player, info = self.player()
        self.assertEqual(finish.validate_player(player, self.finish, self.source), finish.EXPECTED_MANIFEST_SHA256)
        for key, bad in (("ARCHiLiminalPointAssetVersion", 5), ("ARCHiLiminalPointAssetVersion", True),
                         ("ARCHiLiminalPointFinishSHA256", "d" * 64)):
            altered = {**info, key: bad}
            (player / "Contents/Info.plist").write_bytes(plistlib.dumps(altered))
            with self.assertRaises(ValueError):
                finish.validate_player(player, self.finish, self.source)
        (player / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        (player / "Contents/Resources/Data/StreamingAssets/LiminalV008/finish-v11/annotations.bin").write_bytes(b"bad")
        with self.assertRaises(ValueError):
            finish.validate_player(player, self.finish, self.source)

    def test_conflicting_second_destination_is_preserved_before_first_copy(self):
        native, unity = self.targets()
        target = unity / "LiminalV008/finish-v11"
        target.mkdir()
        (target / "authored.txt").write_text("keep")
        with self.assertRaises(ValueError):
            finish.package_finish(self.finish, self.source, native, unity)
        self.assertEqual((target / "authored.txt").read_text(), "keep")
        self.assertFalse((native / "LiminalV008/finish-v11").exists())

    def test_seven_requires_explicit_light_option(self):
        player, info = self.player()
        info["ARCHiLiminalPointAssetVersion"] = 7
        (player / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError): finish.validate_player(player, self.finish, self.source)
        self.assertEqual(finish.validate_player(player, self.finish, self.source, allow_light=True), finish.EXPECTED_MANIFEST_SHA256)

    def test_corruption_during_copy_is_detected(self):
        native, unity = self.targets()
        copytree = shutil.copytree
        def corrupt(source, target, **kwargs):
            result = copytree(source, target, **kwargs)
            (Path(target) / "annotations.bin").write_bytes(b"changed")
            return result
        with patch.object(finish.shutil, "copytree", side_effect=corrupt):
            with self.assertRaisesRegex(ValueError, "Incorrect file size"):
                finish.package_finish(self.finish, self.source, native, unity)


if __name__ == "__main__":
    unittest.main()
