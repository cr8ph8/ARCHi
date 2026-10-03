"""Packaging regressions for retained Seed artwork; no installed app is changed."""
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "script/verify_preserved_liminal_seed.py"
spec = importlib.util.spec_from_file_location("verify_preserved_liminal_seed", SCRIPT)
seed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seed)


class PreservedLiminalSeedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="archi-preserved-seed-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.app = self.root / "ARCHi.app"
        self.art = self.app / seed.APP_ART
        self.art.mkdir(parents=True)
        for name in seed.PNG_PINS:
            shutil.copyfile(ROOT / seed.SOURCE_ART / name, self.art / name)

    def cli(self, app=None):
        result = subprocess.run([sys.executable, str(SCRIPT), "--app", str(app or self.app)],
                                capture_output=True, text=True, check=False)
        return result, json.loads(result.stdout)

    def test_exact_bundle_passes_without_blender_sources(self):
        result, report = self.cli()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue(report["passed"])
        self.assertEqual(report["mode"], "app")
        self.assertEqual(len(report["checks"]), 2)
        self.assertTrue(all(record["dimensions"] == [512, 512] for record in report["checks"]))
        self.assertEqual({record["sha256"] for record in report["checks"]}, set(seed.PNG_PINS.values()))

    def test_missing_image_is_nonzero_and_names_the_required_path(self):
        missing = self.art / "hampton-liminal-garnet-v1.png"
        missing.unlink()
        result, report = self.cli()
        self.assertEqual(result.returncode, 1)
        failed = [record for record in report["checks"] if not record["passed"]]
        self.assertEqual(len(failed), 1)
        self.assertIn(str(missing), failed[0]["error"])
        self.assertIn("Missing", failed[0]["error"])

    def test_valid_png_with_wrong_preserved_hash_is_rejected(self):
        # Both are valid 512x512 Seed PNGs: shape checks alone cannot catch this.
        shutil.copyfile(self.art / "hampton-liminal-seed-v1.png",
                        self.art / "hampton-liminal-garnet-v1.png")
        result, report = self.cli()
        self.assertEqual(result.returncode, 1)
        failed = [record for record in report["checks"] if not record["passed"]]
        self.assertEqual(len(failed), 1)
        self.assertIn("SHA-256 mismatch", failed[0]["error"])

    def test_exact_bytes_behind_file_symlink_are_rejected(self):
        path = self.art / "hampton-liminal-garnet-v1.png"
        outside = self.root / "elsewhere.png"
        path.rename(outside)
        path.symlink_to(outside)
        result, report = self.cli()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("Symbolic-link" in record.get("error", "") for record in report["checks"]))

    def test_symlinked_asset_directory_and_app_root_are_rejected(self):
        relocated = self.root / "art"
        self.art.rename(relocated)
        self.art.symlink_to(relocated, target_is_directory=True)
        result, report = self.cli()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(all("Symbolic-link" in record["error"] for record in report["checks"]))
        alias = self.root / "Alias.app"
        alias.symlink_to(self.app, target_is_directory=True)
        result, report = self.cli(alias)
        self.assertEqual(result.returncode, 1)
        self.assertTrue(all(str(alias) in record["error"] for record in report["checks"]))

    def test_wrong_png_dimensions_have_a_clear_error(self):
        path = self.art / "hampton-liminal-garnet-v1.png"
        content = bytearray(path.read_bytes())
        content[16:20] = struct.pack(">I", 256)
        content[29:33] = struct.pack(">I", zlib.crc32(content[12:29]) & 0xffffffff)
        path.write_bytes(content)
        result, report = self.cli()
        self.assertEqual(result.returncode, 1)
        self.assertTrue(any("512x512, found 256x512" in record.get("error", "") for record in report["checks"]))

    def test_source_mode_also_requires_both_retained_blender_sources(self):
        source_root = self.root / "source"
        source_art = source_root / seed.SOURCE_ART
        source_art.mkdir(parents=True)
        for name in seed.PNG_PINS:
            shutil.copyfile(self.art / name, source_art / name)
        report = seed.verify(source_root)
        self.assertFalse(report["passed"])
        self.assertEqual(report["mode"], "source")
        self.assertEqual(len(report["checks"]), 4)
        self.assertEqual({record["path"] for record in report["checks"] if not record["passed"]},
                         set(seed.BLEND_PINS))


if __name__ == "__main__":
    unittest.main()
