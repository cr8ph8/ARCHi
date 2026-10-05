"""Synthetic packaging gates, including preservation; launches no applications."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "script"))
import package_liminal_light as light
import package_liminal_finish as finish
import liminal_v008_validate as base


class LightPackagingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="archi-light-contract-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.source = self.root / "base"; self.source.mkdir()
        ids = struct.pack("<200000I", *range(200000))
        (self.source / "lod-ids.bin").write_bytes(ids)
        self.base = json.dumps({"lod": {"ids": {"sha256": hashlib.sha256(ids).hexdigest(), "file": "lod-ids.bin"}}}).encode()
        (self.source / "manifest.json").write_bytes(self.base)
        self.finish = self.root / "finish-v11"; self.finish.mkdir()
        (self.finish / "manifest.json").write_text("{}")
        self.light = self.root / "light-v12"; self.light.mkdir()
        self.curves = {"schemaVersion": 1, "paths": [{"id": i, "width": .004, "intensity": 1,
            "color": [1, .2, .02], **{field: [{"sourceID": i, "position": [.1, .2, .3]} for _ in range(12)]
                for field in ("trueKnots", "ballKnots", "seedKnots")}} for i in range(32)]}
        self.manifest = {**light.METADATA, "schemaVersion": 1, "revision": light.REVISION,
            "sourceManifestSHA256": hashlib.sha256(self.base).hexdigest(), "finishManifestSHA256": "b" * 64,
            "sourceBlenderSHA256": "c" * 64, "lodSHA256": hashlib.sha256(ids).hexdigest()}
        stub = patch.object(light, "validate_finish", return_value="b" * 64)
        stub.start(); self.addCleanup(stub.stop)
        pin = patch.object(light, "EXPECTED_MANIFEST_SHA256", "")
        pin.start(); self.addCleanup(pin.stop)
        self.qualify()

    def qualify(self):
        data = json.dumps(self.curves, sort_keys=True).encode()
        (self.light / "curves.json").write_bytes(data)
        self.manifest["curves"] = {"file": "curves.json", "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
        manifest = json.dumps(self.manifest, sort_keys=True).encode()
        (self.light / "manifest.json").write_bytes(manifest)
        light.EXPECTED_MANIFEST_SHA256 = hashlib.sha256(manifest).hexdigest()

    def test_exact_copy_and_readback_preserve_base(self):
        targets = [self.root / name for name in ("native", "unity")]
        for target in targets:
            shutil.copytree(self.source, target / "LiminalV008")
            shutil.copytree(self.finish, target / "LiminalV008/finish-v11")
        expected = light.package_light(self.light, self.source, self.finish, *targets)
        for target in targets:
            self.assertEqual((target / "LiminalV008/manifest.json").read_bytes(), self.base)
            self.assertEqual((target / "LiminalV008/light-v12/curves.json").read_bytes(), (self.light / "curves.json").read_bytes())
        self.assertEqual(expected, light.package_light(self.light, self.source, self.finish, *targets))

    def test_missing_pin_and_changed_bytes_fail_closed(self):
        expected = light.EXPECTED_MANIFEST_SHA256
        light.EXPECTED_MANIFEST_SHA256 = "PENDING"
        with self.assertRaisesRegex(ValueError, "not been pinned"):
            light.validate_light(self.light, self.source, self.finish)
        light.EXPECTED_MANIFEST_SHA256 = expected
        (self.light / "curves.json").write_bytes(b"changed")
        with self.assertRaises(ValueError): light.validate_light(self.light, self.source, self.finish)

    def test_bound_source_finish_and_lod(self):
        for field in ("sourceManifestSHA256", "finishManifestSHA256", "lodSHA256"):
            original = self.manifest[field]; self.manifest[field] = "d" * 64; self.qualify()
            with self.assertRaises(ValueError): light.validate_light(self.light, self.source, self.finish)
            self.manifest[field] = original

    def test_bounded_typed_appearance_and_low_lod_ids(self):
        original = json.dumps(self.curves)
        for key, value in (("width", float("nan")), ("width", True), ("intensity", 9), ("id", True)):
            self.curves = json.loads(original); self.curves["paths"][0][key] = value; self.qualify()
            with self.assertRaises(ValueError): light.validate_light(self.light, self.source, self.finish)
        for key, value in (("sourceID", 50000), ("sourceID", True), ("position", [9, 0, 0])):
            self.curves = json.loads(original); self.curves["paths"][0]["trueKnots"][0][key] = value; self.qualify()
            with self.assertRaises(ValueError): light.validate_light(self.light, self.source, self.finish)

    def test_extra_files_and_symlinks_rejected(self):
        (self.light / "extra").write_text("keep")
        with self.assertRaisesRegex(ValueError, "Unexpected"): light.validate_light(self.light, self.source, self.finish)
        (self.light / "extra").unlink()
        curves = self.light / "curves.json"; curves.rename(self.root / "outside")
        curves.symlink_to(self.root / "outside")
        with self.assertRaisesRegex(ValueError, "regular file"): light.validate_light(self.light, self.source, self.finish)

    def test_player_requires_seven_exact_style_and_digest(self):
        player = self.root / "Player.app"
        embedded = player / "Contents/Resources/Data/StreamingAssets/LiminalV008/light-v12"
        shutil.copytree(self.light, embedded)
        info = {"ARCHiLiminalPointAssetVersion": 7, "ARCHiLiminalPointLightStyle": light.STYLE,
                "ARCHiLiminalPointLightSHA256": light.EXPECTED_MANIFEST_SHA256}
        plist = player / "Contents/Info.plist"; plist.write_bytes(plistlib.dumps(info))
        self.assertEqual(light.validate_player(player, self.light, self.source, self.finish), light.EXPECTED_MANIFEST_SHA256)
        for key, bad in (("ARCHiLiminalPointAssetVersion", 6), ("ARCHiLiminalPointAssetVersion", True),
                         ("ARCHiLiminalPointLightStyle", "old"), ("ARCHiLiminalPointLightSHA256", "a" * 64)):
            plist.write_bytes(plistlib.dumps({**info, key: bad}))
            with self.assertRaises(ValueError): light.validate_player(player, self.light, self.source, self.finish)

    def test_conflicting_second_target_blocks_first_copy(self):
        targets = [self.root / name for name in ("native", "unity")]
        for target in targets:
            shutil.copytree(self.source, target / "LiminalV008")
            shutil.copytree(self.finish, target / "LiminalV008/finish-v11")
        conflict = targets[1] / "LiminalV008/light-v12"; conflict.mkdir()
        (conflict / "authored.txt").write_text("keep")
        with self.assertRaises(ValueError): light.package_light(self.light, self.source, self.finish, *targets)
        self.assertEqual((conflict / "authored.txt").read_text(), "keep")
        self.assertFalse((targets[0] / "LiminalV008/light-v12").exists())

    def test_assembled_children_use_real_pinned_finish_and_light_validators(self):
        # This case replaces the ordinary suite's finish stub with the actual
        # validator. Only the trusted pin is synthetic, local to this fixture.
        annotations = struct.pack("<3fI", 1, 0, 0, 1) * finish.COUNT
        (self.finish / "annotations.bin").write_bytes(annotations)
        manifest = {**finish.DISPLAY_METADATA, "schemaVersion": 1, "revision": finish.REVISION,
                    "sourceManifestSHA256": hashlib.sha256(self.base).hexdigest(),
                    "lodSHA256": self.manifest["lodSHA256"], "blenderSHA256": "c" * 64,
                    "pointCount": finish.COUNT, "stride": finish.STRIDE,
                    "annotations": base.file_ref(self.finish / "annotations.bin", self.finish)}
        (self.finish / "manifest.json").write_text(json.dumps(manifest))
        pin = base.sha256(self.finish / "manifest.json")
        self.manifest["finishManifestSHA256"] = pin
        self.qualify()
        shutil.copytree(self.finish, self.source / "finish-v11")
        shutil.copytree(self.light, self.source / "light-v12")
        with patch.object(finish, "EXPECTED_MANIFEST_SHA256", pin), \
                patch.object(light, "validate_finish", finish.validate_finish):
            self.assertEqual(base._validated_display_files(self.source, allow_finish=True, allow_light=True), {
                "finish-v11/manifest.json", "finish-v11/annotations.bin", "light-v12/manifest.json", "light-v12/curves.json"})
            for name in ("manifest.json", "curves.json"):
                with self.subTest(changed=name):
                    path = self.source / "light-v12" / name
                    original = path.read_bytes(); path.write_bytes(original + b"changed")
                    with self.assertRaises(ValueError):
                        base._validated_display_files(self.source, allow_finish=True, allow_light=True)
                    path.write_bytes(original)
            child = self.source / "light-v12"
            child.rename(self.root / "saved-light"); child.symlink_to(self.root / "saved-light")
            with self.assertRaisesRegex(ValueError, "regular directory"):
                base._validated_display_files(self.source, allow_finish=True, allow_light=True)


if __name__ == "__main__": unittest.main()
