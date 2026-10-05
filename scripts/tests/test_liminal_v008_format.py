"""Synthetic small format fixtures; never production v008 or Houdini evidence."""
import array
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2]/"script"
sys.path.insert(0, str(SCRIPT))
import liminal_v008_validate as fmt
import liminal_v008_export as exporter
import package_liminal_finish as finish
import package_liminal_v008 as packager


def comparison(runtime_count=200000):
    return {"schema": "archi-liminal-motion-comparison/v2", "status": "passed", "hipSHA256": fmt.HIP_SHA,
            "node": fmt.NODE, "sourceCooked": True, "sampleFrames": list(range(1, 121)),
            "runtimePointCount": runtime_count, "endpointFrames": list(fmt.POSES.values()),
            "checks": {"identityError": 0., "pathLimitError": 0., "endpointPoseError": 0.,
                       "poseAttributeError": 0., "widthError": 0., "idMismatchCount": 0},
            "interpolation": {"evaluated": True, "subframes": fmt.SUBFRAMES,
                              "comparedPointCount": runtime_count, **{k: 0. for k in fmt.LIMITS}},
            "limits": fmt.LIMITS.copy()}


class LiminalFormatTests(unittest.TestCase):
    def test_rank_is_nested_and_pinned_to_source_and_ids(self):
        prefix = ("archi-liminal-lod/v1\n"+fmt.HIP_SHA+"\n").encode()
        expected = sorted(range(32), key=lambda i: (hashlib.sha256(prefix+str(i).encode()).digest(), i))
        self.assertEqual(list(fmt.ranked_ids(32, 16)), expected[:16])
        self.assertEqual(list(fmt.ranked_ids(32, 8)), expected[:8])
        self.assertEqual(fmt.little_bytes(array.array("I", [1, 256])), b"\x01\x00\x00\x00\x00\x01\x00\x00")

    def test_pack_keeps_real_rows_and_comparison_detects_motion_error(self):
        attrs = {"P": array.array("f", [1, 2, 3, 4, 5, 6]), "Cd": array.array("f", [.1, .2, .3, .4, .5, .6]),
                 "pscale": array.array("f", [.001, .002]), "heat": array.array("f", [2, 4])}
        raw = exporter.pack_rows(attrs, [1, 0])
        self.assertEqual(len(raw), 64)
        self.assertEqual(fmt.SAMPLE.unpack_from(raw)[:3], (4., 5., 6.))
        before = fmt.SAMPLE.pack(0, 0, 0, 0, 0, 0, .01, 1)
        after = fmt.SAMPLE.pack(2, 0, 0, 1, 1, 1, .01, 3)
        actual = fmt.SAMPLE.pack(2, .02, 0, 1, 1, 1, .01, 3)
        errors = exporter.comparison_errors(actual, before, after, .5)
        self.assertAlmostEqual(errors["position"], .02)
        receipt = comparison()
        receipt["interpolation"].update(errors)
        with self.assertRaisesRegex(fmt.InvalidAsset, "exceeds limits"):
            fmt.validate_comparison(receipt)

    def test_source_clock_holds_lower_then_rounds_half_up(self):
        before = fmt.SAMPLE.pack(0, 0, 0, 0, 0, 0, .01, 1)
        after = fmt.SAMPLE.pack(2, 0, 0, 1, 1, 1, .02, 3)
        for fraction, actual in ((.25, before), (.49, before), (.5, after), (.75, after)):
            self.assertEqual(exporter.comparison_errors(actual, before, after, fraction), dict.fromkeys(fmt.LIMITS, 0.))
        old = comparison(); old['schema'] = 'archi-liminal-motion-comparison/v1'
        with self.assertRaises(fmt.InvalidAsset): fmt.validate_comparison(old)
        missing = comparison(); missing['interpolation']['subframes'] = fmt.SUBFRAMES[::3]
        with self.assertRaises(fmt.InvalidAsset): fmt.validate_comparison(missing)

    def test_comparison_rejects_unexecuted_incomplete_or_false_ids(self):
        fmt.validate_comparison(comparison())
        for path, value in ((('sourceCooked',), False), (('sampleFrames',), [24, 66, 108]),
                            (('checks', 'idMismatchCount'), True), (('interpolation', 'evaluated'), False),
                            (('interpolation', 'position'), float('nan'))):
            receipt = comparison()
            target = receipt
            for part in path[:-1]: target = target[part]
            target[path[-1]] = value
            with self.assertRaises(fmt.InvalidAsset): fmt.validate_comparison(receipt)

    def test_paths_json_and_source_pin_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/"ok.bin").write_bytes(b"a")
            (root/"link.bin").symlink_to(root/"ok.bin")
            for name in ("../ok.bin", "/tmp/ok.bin", "a/../ok.bin", "./ok.bin", "link.bin", "a\\b"):
                with self.assertRaises(fmt.InvalidAsset): fmt.safe_file(root, name)
            for content in ('{"same":1,"same":2}', '{"n":NaN}'):
                (root/"bad.json").write_text(content)
                with self.assertRaises(fmt.InvalidAsset): fmt.read_json(root/"bad.json")
            wrong = root/"Liminal-v008-lion-spin-blend.hiplc"
            wrong.write_bytes(b"v002 is not v008")
            with self.assertRaisesRegex(fmt.InvalidAsset, "SHA256 mismatch"):
                exporter.check_source(wrong)

    def test_reference_projection_is_transparent_and_uses_fixed_camera(self):
        bounds = {"min": [-1., -2., -3.], "max": [1., 2., 3.], "maximumRadius": .01, "maximumEmission": 2.}
        camera = fmt.reference_camera(bounds)
        self.assertEqual(camera["center"], [0., 0., 0.])
        self.assertAlmostEqual(camera["span"], 6.02*1.12)
        png = fmt.reference_png([(0, 0, 0, 1, .5, .1, .01, 2)], camera)
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">IIBBBBB", png[16:29]), (512, 512, 8, 6, 0, 0, 0))
        self.assertEqual(png, fmt.reference_png([(0, 0, 0, 1, .5, .1, .01, 2)], camera))
        pixels = fmt.reference_png_pixels(png)
        self.assertEqual(pixels[1:5], b"\0\0\0\0")
        with self.assertRaises(fmt.InvalidAsset): fmt.reference_png_pixels(png[:-1])

    def fixture(self, root, ids):
        rows = [(float(i), float(i%2), -float(i), .5, .2, .1, .001, 1.) for i in range(8)]
        (root/"endpoints.bin").write_bytes(b"".join(fmt.MASTER.pack(i, *(row*3)) for i, row in enumerate(rows)))
        (root/"master-cohorts.bin").write_bytes(b"".join(struct.pack("<II", i, 7-i) for i in range(8)))
        (root/"lod-ids.bin").write_bytes(fmt.little_bytes(ids))
        (root/"frames").mkdir()
        (root/"frames/0001.bin").write_bytes(b"".join(fmt.SAMPLE.pack(*rows[i]) for i in ids))
        exporter.write_json(root/"comparison.json", comparison(4))
        ref = lambda name: fmt.file_ref(root/name, root)
        bounds = fmt.empty_bounds()
        for row in fmt.sample_rows(root/"frames/0001.bin"): fmt.include_row(bounds, row)
        for row in rows: fmt.include_row(bounds, fmt.SAMPLE.unpack(fmt.SAMPLE.pack(*row)))
        manifest = {"schema": fmt.SCHEMA, "assetID": "liminal-v008",
                    "source": {"hipSHA256": fmt.HIP_SHA, "houdiniVersion": "22.0.429", "node": fmt.NODE,
                               "originalUnchanged": True, "dependencies": [{"file": p, "sha256": h, "bytes": n} for p, h, n in fmt.DEPENDENCIES]},
                    "pointCount": 8, "runtimePointCount": 4, "encoding": fmt.ENCODING,
                    "coordinates": {"space": "houdini-sop-local", "handedness": "right", "upAxis": "+Y", "units": "authored-scene-units",
                                    "nativeMapping": [1, 1, 1], "unityMapping": [1, 1, -1], "objectToWorldRowMajor": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]},
                    "appearance": fmt.APPEARANCE, "timeline": {"fps": 24, "firstFrame": 1, "lastFrame": 120, "interpolation": "nearest-half-up", "poseFrames": fmt.POSES},
                    "bounds": bounds, "master": ref("endpoints.bin"), "cohorts": ref("master-cohorts.bin"),
                    "lod": {"algorithm": "sha256-rank-v1", "counts": [50000, 100000, 200000], "ids": ref("lod-ids.bin")},
                    "frames": [{"frame": i, **ref("frames/0001.bin")} for i in range(1, 121)],
                    "motionControls": fmt.CONTROL_VALUES, "endpointImages": {"status": "unavailable", "camera": None,
                    "images": [], "reason": "Synthetic format test only."}, "comparison": ref("comparison.json")}
        (root/"manifest.json").write_text(json.dumps(manifest))
        return manifest

    def test_complete_scaled_fixture_rejects_corruption_and_false_endpoint_join(self):
        ids = fmt.ranked_ids(8, 4)
        with tempfile.TemporaryDirectory() as directory, mock.patch.multiple(fmt, COUNT=8, RUNTIME_COUNT=4), \
                mock.patch.object(fmt, "ranked_ids", return_value=ids):
            root = Path(directory)
            manifest = self.fixture(root, ids)
            self.assertEqual(fmt.validate_package(root)["status"], "passed")
            raw = bytearray((root/"endpoints.bin").read_bytes())
            raw[ids[0]*100+4:ids[0]*100+8] = struct.pack("<f", .125)
            (root/"endpoints.bin").write_bytes(raw)
            with self.assertRaisesRegex(fmt.InvalidAsset, "digest mismatch"):
                fmt.validate_package(root)
            manifest["master"] = fmt.file_ref(root/"endpoints.bin", root)
            (root/"manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(fmt.InvalidAsset, "endpoint LOD"):
                fmt.validate_package(root)

    def test_endpoint_receipt_binds_pixels_and_sample_hashes(self):
        ids = fmt.ranked_ids(8, 4)
        with tempfile.TemporaryDirectory() as directory, mock.patch.multiple(fmt, COUNT=8, RUNTIME_COUNT=4), \
                mock.patch.object(fmt, "ranked_ids", return_value=ids):
            root = Path(directory)
            manifest = self.fixture(root, ids)
            manifest["endpointImages"] = exporter.endpoint_images(root, manifest["bounds"], manifest["frames"], manifest["master"])
            (root/"manifest.json").write_text(json.dumps(manifest))
            self.assertEqual(fmt.validate_package(root)["endpointImageStatus"], "qualified")
            image = manifest["endpointImages"]["images"][0]
            (root/image["file"]).write_bytes(fmt.reference_png([], manifest["endpointImages"]["camera"]))
            image.update(fmt.file_ref(root/image["file"], root))
            (root/"manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(fmt.InvalidAsset, "pixels"):
                fmt.validate_package(root)

    @contextmanager
    def assembled_fixture(self, qualified_images=False):
        """Small base and real finish validation with a process-local synthetic pin."""
        ids = fmt.ranked_ids(8, 4)
        with tempfile.TemporaryDirectory() as directory, mock.patch.multiple(fmt, COUNT=8, RUNTIME_COUNT=4), \
                mock.patch.object(fmt, "ranked_ids", return_value=ids), mock.patch.object(finish, "COUNT", 4):
            root = Path(directory) / "source"; root.mkdir()
            manifest = self.fixture(root, ids)
            if qualified_images:
                manifest["endpointImages"] = exporter.endpoint_images(root, manifest["bounds"], manifest["frames"], manifest["master"])
                (root / "manifest.json").write_text(json.dumps(manifest))
            child = root / "finish-v11"; child.mkdir()
            (child / "annotations.bin").write_bytes(struct.pack("<3fI", 1, 0, 0, 1) * 4)
            data = {**finish.DISPLAY_METADATA, "schemaVersion": 1, "revision": finish.REVISION,
                    "sourceManifestSHA256": fmt.sha256(root / "manifest.json"),
                    "lodSHA256": manifest["lod"]["ids"]["sha256"], "blenderSHA256": "c" * 64,
                    "pointCount": 4, "stride": finish.STRIDE,
                    "annotations": fmt.file_ref(child / "annotations.bin", child)}
            (child / "manifest.json").write_text(json.dumps(data))
            with mock.patch.object(finish, "EXPECTED_MANIFEST_SHA256", fmt.sha256(child / "manifest.json")):
                yield root

    def test_assembled_finish_is_explicit_and_base_corruption_still_rejected(self):
        with self.assembled_fixture() as root:
            with self.assertRaisesRegex(fmt.InvalidAsset, "unexpected files"):
                fmt.validate_package(root)
            self.assertEqual(fmt.validate_package(root, allow_finish=True)["status"], "passed")
            with self.assertRaisesRegex(fmt.InvalidAsset, "requires explicit finish"):
                fmt.validate_package(root, allow_light=True)
            with (root / "endpoints.bin").open("r+b") as stream:
                stream.write(b"changed")
            with self.assertRaisesRegex(fmt.InvalidAsset, "digest mismatch"):
                fmt.validate_package(root, allow_finish=True)

    def test_assembled_opt_in_rejects_altered_unknown_and_linked_children(self):
        for mutation in ("manifest", "annotations", "extra-file", "empty-directory", "child-link", "file-link", "unselected-light"):
            with self.subTest(mutation=mutation), self.assembled_fixture() as root:
                child = root / "finish-v11"
                if mutation in ("manifest", "annotations"):
                    path = child / ("manifest.json" if mutation == "manifest" else "annotations.bin")
                    path.write_bytes(path.read_bytes() + b"changed")
                elif mutation == "extra-file":
                    (root / "unknown.bin").write_bytes(b"preserve")
                elif mutation == "empty-directory":
                    (root / "unknown-child").mkdir()
                elif mutation in ("child-link", "file-link"):
                    path = child if mutation == "child-link" else child / "annotations.bin"
                    outside = root.parent / "retained"
                    path.rename(outside); path.symlink_to(outside)
                else:
                    (root / "light-v12").mkdir()
                    (root / "light-v12/manifest.json").write_text("{}")
                with self.assertRaises(ValueError):
                    fmt.validate_package(root, allow_finish=True)

    def test_assembled_packaging_preserves_bytes_and_stripped_unity_base(self):
        with self.assembled_fixture(qualified_images=True) as source:
            before = {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()}
            qualification = source.parent / "qualification.json"
            qualification.write_text(json.dumps({"schemaVersion": 1, "assetID": "liminal-v008",
                "manifestSHA256": fmt.sha256(source / "manifest.json"), "sourceCooked": True,
                "nativeEndpointsPassed": True, "unityEndpointsPassed": True, "installedWalkthroughPassed": False}))
            native, unity = source.parent / "native", source.parent / "unity"
            shutil.copytree(source, unity / "LiminalV008", ignore=shutil.ignore_patterns("finish-v11"))
            result = packager.package(source, qualification, native, unity, allow_finish=True)
            self.assertFalse(result["installedWalkthroughPassed"])
            self.assertEqual(before, {p.relative_to(source): p.read_bytes() for p in source.rglob("*") if p.is_file()})
            for name, data in before.items():
                self.assertEqual((native / "LiminalV008" / name).read_bytes(), data)
                if name.parts[0] != "finish-v11":
                    self.assertEqual((unity / "LiminalV008" / name).read_bytes(), data)
            # The existing child packager completes the deliberately stripped helper.
            finish.package_finish(source / "finish-v11", source, native, unity)
            for name, data in before.items():
                self.assertEqual((unity / "LiminalV008" / name).read_bytes(), data)
            (native / "LiminalV008/finish-v11/annotations.bin").write_bytes(b"altered")
            with self.assertRaises(ValueError):
                packager.package(source, qualification, native, unity, allow_finish=True)


if __name__ == "__main__":
    unittest.main()
