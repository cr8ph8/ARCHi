"""Synthetic evidence/launcher regressions. No test executes Unity or qualifies rendering."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("orb_runtime_receipt", ROOT / "script/orb_runtime_receipt.py")
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


def png():
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 960, 720, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress((b"\0" + b"\0" * 2880) * 720)) + chunk(b"IEND", b""))


class OrbRuntimeAcceptanceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="archi-orb-evidence-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.repo, self.output = self.root / "source", self.root / "synthetic-evidence"
        self.output.mkdir()
        for name in evidence.SOURCE_PATHS:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("synthetic source fixture: " + name)
        for name in evidence.CAPTURE_PATHS:
            (self.output / name).write_bytes(png())
        self.receipt = {
            "schema": evidence.SCHEMA, "passed": True, "failedAssertions": 0, "errors": [],
            "unityVersion": evidence.UNITY_VERSION, "graphicsAPI": "SYNTHETIC-TEST-ONLY", "graphicsDevice": "NO-UNITY-RUN",
            "outputDirectory": str(self.output), "ticks": 120, "renderedPlayerFrames": 3, "minimumSampledClearance": .64,
            "assertions": [{"name": name, "passed": True} for name in sorted(evidence.REQUIRED_ASSERTIONS)],
            "sources": [{"path": name, "sha256": hashlib.sha256((self.repo / name).read_bytes()).hexdigest()}
                        for name in sorted(evidence.SOURCE_PATHS)],
            "captures": [{"file": name, "sha256": hashlib.sha256((self.output / name).read_bytes()).hexdigest(), "changedPixels": 30}
                         for name in sorted(evidence.CAPTURE_PATHS)],
        }
        self.receipt["passedAssertions"] = len(self.receipt["assertions"])
        self.log = self.output.with_name(self.output.name + ".editor.log")
        self.log.write_text("SYNTHETIC TEST ONLY\nARCHI_ORB_RUNTIME_PASS " + str(self.output) + "\n")

    def write(self, receipt=None):
        (self.output / "acceptance.json").write_text(json.dumps(self.receipt if receipt is None else receipt))

    def verify(self):
        self.write()
        return evidence.verify(self.repo, self.output)

    def test_complete_synthetic_evidence_is_internally_consistent(self):
        self.assertEqual(self.verify()["passedAssertions"], len(evidence.REQUIRED_ASSERTIONS))

    def test_wrong_version_null_device_and_false_success_are_rejected(self):
        for field, value in (("unityVersion", "wrong"), ("graphicsAPI", "Null"), ("graphicsDevice", ""),
                             ("passed", False), ("failedAssertions", 1), ("passedAssertions", True), ("errors", ["failure"]),
                             ("ticks", 0), ("renderedPlayerFrames", 0), ("minimumSampledClearance", float("nan")),
                             ("minimumSampledClearance", .6), ("outputDirectory", str(self.root))):
            with self.subTest(field=field, value=value):
                changed = copy.deepcopy(self.receipt); changed[field] = value; self.write(changed)
                with self.assertRaises(ValueError): evidence.verify(self.repo, self.output)

    def test_failed_missing_duplicate_and_miscounted_assertions_are_rejected(self):
        for change in ("failed", "missing", "duplicate", "miscounted"):
            with self.subTest(change=change):
                receipt = copy.deepcopy(self.receipt)
                if change == "failed": receipt["assertions"][0]["passed"] = False
                if change == "missing": receipt["assertions"].pop()
                if change == "duplicate": receipt["assertions"][0] = receipt["assertions"][1]
                if change != "miscounted": receipt["passedAssertions"] = len(receipt["assertions"])
                else: receipt["passedAssertions"] += 1
                self.write(receipt)
                with self.assertRaises(ValueError): evidence.verify(self.repo, self.output)

    def test_missing_duplicate_and_escaping_inventory_paths_are_rejected(self):
        for label in ("sources", "captures"):
            for change in ("missing", "duplicate", "escape"):
                with self.subTest(label=label, change=change):
                    receipt = copy.deepcopy(self.receipt)
                    if change == "missing": receipt[label].pop()
                    if change == "duplicate": receipt[label].append(receipt[label][0])
                    if change == "escape": receipt[label][0]["path" if label == "sources" else "file"] = "../elsewhere"
                    self.write(receipt)
                    with self.assertRaises(ValueError): evidence.verify(self.repo, self.output)

    def test_changed_sources_and_captures_are_rejected(self):
        for path in (self.repo / sorted(evidence.SOURCE_PATHS)[0], self.output / "lamp.png"):
            with self.subTest(path=path):
                original = path.read_bytes(); path.write_bytes(original + b"changed")
                with self.assertRaisesRegex(ValueError, "hash mismatch"): self.verify()
                path.write_bytes(original)

    def test_rehashed_non_png_and_missing_particle_contribution_are_rejected(self):
        path = self.output / "lamp.png"; path.write_bytes(b"not a PNG")
        row = next(row for row in self.receipt["captures"] if row["file"] == "lamp.png")
        row["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        with self.assertRaisesRegex(ValueError, "PNG"): self.verify()
        path.write_bytes(png()); row["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
        next(row for row in self.receipt["captures"] if row["file"] == "lamp-attention-hidden.png")["changedPixels"] = 0
        with self.assertRaisesRegex(ValueError, "particle difference"): self.verify()

    def test_missing_log_marker_and_symlinked_capture_are_rejected(self):
        self.log.write_text("SYNTHETIC incomplete run")
        with self.assertRaisesRegex(ValueError, "completion marker"): self.verify()
        self.log.write_text("ARCHI_ORB_RUNTIME_PASS " + str(self.output))
        path = self.output / "lamp.png"; destination = self.root / "external.png"
        path.rename(destination); path.symlink_to(destination)
        with self.assertRaisesRegex(ValueError, "symbolic link"): self.verify()

    def launcher(self, mode):
        # Confined source copy and fake executable: exercise orchestration, never an installed Editor.
        (self.repo / "script").mkdir(exist_ok=True)
        for name in ("run_orb_runtime_acceptance.sh", "orb_runtime_receipt.py"):
            shutil.copyfile(ROOT / "script" / name, self.repo / "script" / name)
        editor = self.root / "synthetic_editor.py"
        editor.write_text("""#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args=sys.argv[1:]
assert '-nographics' not in args and '-quit' not in args
assert args[args.index('-executeMethod')+1] == 'OrbRoomRuntimeValidation.Validate'
mode=os.environ['ARCHI_ORB_TEST_MODE']
if mode == 'nonzero': sys.exit(17)
if mode == 'missing': sys.exit(0)
output=pathlib.Path(args[args.index('-archiOrbAcceptanceOutput')+1])
if mode == 'complete':
    shutil.copytree(os.environ['ARCHI_ORB_TEST_TEMPLATE'], output)
    receipt=json.loads((output/'acceptance.json').read_text());receipt['outputDirectory']=str(output)
    (output/'acceptance.json').write_text(json.dumps(receipt))
    pathlib.Path(args[args.index('-logFile')+1]).write_text('SYNTHETIC ONLY\\nARCHI_ORB_RUNTIME_PASS ' + str(output))
    sys.exit(0)
output.mkdir()
(output/'acceptance.json').write_text(json.dumps({'schema':'archi-orb-room-runtime-acceptance/v1','passed':True,'failedAssertions':0,'passedAssertions':1,'errors':[]}))
""")
        editor.chmod(0o700)
        return subprocess.run(["bash", str(self.repo / "script/run_orb_runtime_acceptance.sh"), "--editor", str(editor),
                               "--output", str(self.root / ("launch-" + mode))], text=True, capture_output=True,
                              env={**os.environ, "ARCHI_ORB_TEST_MODE": mode,
                                   "ARCHI_ORB_TEST_TEMPLATE": str(self.output)}, timeout=10)

    def test_launcher_rejects_incomplete_success_receipt(self):
        result = self.launcher("incomplete")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("wrong Unity version", result.stderr)

    def test_launcher_requires_receipt_and_propagates_editor_failure(self):
        self.assertNotEqual(self.launcher("missing").returncode, 0)
        self.assertEqual(self.launcher("nonzero").returncode, 17)

    def test_launcher_complete_synthetic_contract_passes(self):
        self.write()
        result = self.launcher("complete")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_launcher_help_and_missing_editor(self):
        script = ROOT / "script/run_orb_runtime_acceptance.sh"
        self.assertEqual(subprocess.run(["bash", str(script), "--help"], capture_output=True).returncode, 0)
        result = subprocess.run(["bash", str(script), "--editor", str(self.root / "missing-editor")], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"No Unity run occurred", result.stderr)

    def test_launcher_refuses_existing_and_source_destinations(self):
        for destination in (self.output, ROOT / "new-source-directory"):
            with self.subTest(destination=destination):
                result = subprocess.run(["bash", str(ROOT / "script/run_orb_runtime_acceptance.sh"),
                    "--editor", "/usr/bin/true", "--output", str(destination)],
                    capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
