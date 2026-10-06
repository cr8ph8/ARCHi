"""Content and failure-boundary checks; no compiler, signer or app is invoked."""
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
import uuid


HELPER = Path(__file__).resolve().parents[2] / "script/native_build_identity.py"
spec = importlib.util.spec_from_file_location("native_build_identity", HELPER)
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


class NativeBuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="archi-identity-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "source"
        for name in identity.REQUIRED:
            path = self.repo / name
            if name.endswith(".swift"):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('.package(path: "../shared/ARCHiSpatial")' if name.startswith("desktop/") else "// shared")
            else:
                path.mkdir(parents=True, exist_ok=True)
        (self.repo / "script").mkdir()
        for name in ("build_and_run.sh", "native_build_identity.py", "package_fixture.py"):
            (self.repo / "script" / name).write_text("# synthetic recipe\n")
        (self.repo / "desktop/Sources/main.swift").write_text("// native source")
        (self.repo / "shared/ARCHiSpatial/Sources/ImageRegion.swift").write_text("// dependency")
        self.snapshot = self.root / "before.json"

    def capture(self):
        identity.capture(self.repo, self.snapshot, verification_requested=False, compiler="Swift fixture")

    def app(self, name):
        app = self.root / (name + ".app")
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Resources/UnityCompanion.app").mkdir(parents=True)
        (app / "Contents/MacOS/ARCHiDesktop").write_bytes(b"fixture executable")
        (app / "Contents/Resources/UnityCompanion.app/player").write_bytes(b"external player input")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.quotient.archi.desktop.review", "CFBundleShortVersionString": "0.7.0"}))
        return app

    def test_dirty_untracked_dependency_resource_recipe_and_optional_inputs_change_identity(self):
        before = identity.source_inputs(self.repo)["sourceContentID"]
        for name in ("desktop/Sources/main.swift", "desktop/Sources/new-untracked.swift",
                     "shared/ARCHiSpatial/Sources/ImageRegion.swift", "desktop/Sources/Resources/new.bin",
                     "script/package_fixture.py", "desktop/Package.resolved"):
            with self.subTest(input=name):
                path = self.repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"changed actual bytes, without any Git commit")
                after = identity.source_inputs(self.repo)["sourceContentID"]
                self.assertNotEqual(before, after)
                before = after

    def test_identical_bytes_at_different_checkout_paths_have_same_source_identity(self):
        other = self.root / "another source location"
        shutil.copytree(self.repo, other)
        self.assertEqual(identity.source_inputs(self.repo), identity.source_inputs(other))

    def test_missing_wrong_type_linked_and_special_inputs_fail_closed(self):
        dependency = self.repo / "shared/ARCHiSpatial/Package.swift"
        dependency.unlink()
        with self.assertRaisesRegex(ValueError, "Missing required"):
            identity.source_inputs(self.repo)
        dependency.mkdir()
        with self.assertRaisesRegex(ValueError, "Wrong native input type"):
            identity.source_inputs(self.repo)
        dependency.rmdir()
        outside = self.root / "external.swift"
        outside.write_text("// external")
        dependency.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "link"):
            identity.source_inputs(self.repo)
        dependency.unlink()
        dependency.write_text("// shared")
        fifo = self.repo / "desktop/Sources/unexpected.swift"
        os.mkfifo(fifo)
        with self.assertRaisesRegex(ValueError, "Unsupported build input"):
            identity.source_inputs(self.repo)

    def test_new_dependency_requires_scope_review(self):
        path = self.repo / "desktop/Package.swift"
        path.write_text(path.read_text() + ', .package(path: "../../unrecorded")')
        with self.assertRaisesRegex(ValueError, "dependency graph changed"):
            identity.source_inputs(self.repo)

    def test_unique_candidates_same_content_valid_versions_and_no_private_source_paths(self):
        self.capture()
        now = datetime(2026, 10, 5, 12, 3, tzinfo=timezone.utc)
        receipts = [identity.seal(self.repo, self.snapshot, self.app(name), now=now) for name in ("one", "two")]
        self.assertNotEqual(receipts[0]["candidateID"], receipts[1]["candidateID"])
        self.assertEqual(receipts[0]["contentID"], receipts[1]["contentID"])
        for receipt in receipts:
            self.assertEqual(str(uuid.UUID(receipt["candidateID"])), receipt["candidateID"])
            self.assertRegex(receipt["bundleVersion"], r"^[1-9]\d{0,3}\.\d{1,2}\.\d{1,2}$")
            self.assertNotIn(str(self.root), json.dumps(receipt))
            self.assertIn("not final signed artifact hashes", receipt["scope"])
        info = plistlib.loads((self.root / "one.app/Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "0.7.0")
        self.assertEqual(info["ARCHiCandidateID"], receipts[0]["candidateID"])

    def test_external_packaged_content_changes_identity_without_source_path_disclosure(self):
        self.capture()
        one = self.app("one")
        two = self.app("two")
        (two / "Contents/Resources/UnityCompanion.app/player").write_bytes(b"different player")
        a = identity.seal(self.repo, self.snapshot, one)
        b = identity.seal(self.repo, self.snapshot, two)
        self.assertEqual(a["sourceContentID"], b["sourceContentID"])
        self.assertNotEqual(a["preSignPayloadID"], b["preSignPayloadID"])
        self.assertNotEqual(a["contentID"], b["contentID"])

    def test_changed_source_and_missing_or_escaping_payload_never_stamp_identity(self):
        self.capture()
        app = self.app("changed")
        source = self.repo / "desktop/Sources/main.swift"
        original = source.read_bytes()
        source.write_text("// changed after compile")
        with self.assertRaisesRegex(ValueError, "inputs changed"):
            identity.seal(self.repo, self.snapshot, app)
        self.assertFalse((app / identity.RECEIPT).exists())
        source.write_bytes(original)
        (app / "Contents/MacOS/ARCHiDesktop").unlink()
        with self.assertRaisesRegex(ValueError, "Missing packaged input"):
            identity.seal(self.repo, self.snapshot, app)
        (app / "Contents/MacOS/ARCHiDesktop").symlink_to(source)
        with self.assertRaisesRegex(ValueError, "link"):
            identity.seal(self.repo, self.snapshot, app)
        self.assertFalse((app / identity.RECEIPT).exists())

    def test_candidate_and_snapshot_cannot_be_silently_replaced(self):
        self.capture()
        with self.assertRaises(FileExistsError):
            self.capture()
        app = self.app("once")
        first = identity.seal(self.repo, self.snapshot, app)
        with self.assertRaisesRegex(ValueError, "already has"):
            identity.seal(self.repo, self.snapshot, app)
        self.assertEqual(first, json.loads((app / identity.RECEIPT).read_text()))


if __name__ == "__main__":
    unittest.main()
