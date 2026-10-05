"""Exercise staging and collision handling with disposable bundles and fake build tools.

No compiler, signer, installed application, process inventory or app launcher is
invoked. Filesystem copies and moves are real, inside disposable directories.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "script/build_and_run.sh"
FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, sys, time
name = pathlib.Path(sys.argv[0]).name
with open(os.environ["ARCHI_TEST_TRACE"], "a") as log:
    log.write(json.dumps([name] + sys.argv[1:]) + "\n")
if name == "pgrep":
    sys.exit(1)
if name == "open":
    sys.exit(90)
if name == "plutil" and sys.argv[1] in ("-insert", "-replace"):
    path = pathlib.Path(sys.argv[-1])
    info = plistlib.loads(path.read_bytes())
    info[sys.argv[2]] = sys.argv[4] == "YES" if sys.argv[3] == "-bool" else sys.argv[4]
    path.write_bytes(plistlib.dumps(info))
if name == "mv":
    collision = os.environ.get("ARCHI_TEST_PROMOTION_COLLISION")
    if collision and "-n" in sys.argv:
        target = pathlib.Path(collision)
        target.mkdir()
        (target / "authored.txt").write_text("preserve concurrent bundle")
    os.execv("/bin/mv", ["mv"] + sys.argv[1:])
if name == "swift":
    if "--version" in sys.argv:
        print("Swift version fixture (no compiler invoked)")
        sys.exit(0)
    gate = os.environ.get("ARCHI_TEST_BUILD_GATE")
    if gate and "--show-bin-path" not in sys.argv:
        deadline = time.monotonic() + 8
        while not pathlib.Path(gate).exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        if not pathlib.Path(gate).exists():
            sys.exit(91)
    if "--show-bin-path" in sys.argv:
        print(os.environ["ARCHI_TEST_BIN"])
    elif os.environ.get("ARCHI_TEST_SOURCE_MUTATION"):
        pathlib.Path(os.environ["ARCHI_TEST_SOURCE_MUTATION"]).write_text("changed during fake compile")
if name == "codesign" and "--force" in sys.argv and pathlib.Path(sys.argv[-1]).name == "ARCHi.app":
    app = pathlib.Path(sys.argv[-1])
    receipt = json.loads((app / "Contents/Resources/ARCHiBuildIdentity.json").read_text())
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert receipt["candidateID"] == info["ARCHiCandidateID"]
    assert receipt["sourceContentID"] == info["ARCHiSourceContentID"]
    with open(os.environ["ARCHI_TEST_TRACE"], "a") as log:
        log.write(json.dumps(["identity-observed-at-outer-sign", receipt["candidateID"]]) + "\n")
if name == "codesign" and "--verify" in sys.argv and ".archi-install." in sys.argv[-1]:
    collision = os.environ.get("ARCHI_TEST_COLLISION")
    if collision:
        target = pathlib.Path(collision)
        target.mkdir()
        (target / "authored.txt").write_text("preserve concurrent bundle")
'''


class BuildAndRunStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="archi-stage-contract-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        script = self.root / "repo/script/build_and_run.sh"
        script.parent.mkdir(parents=True)
        shutil.copy2(SCRIPT, script)
        shutil.copy2(SCRIPT.parent / "verify_preserved_liminal_seed.py", script.parent)
        shutil.copy2(SCRIPT.parent / "native_build_identity.py", script.parent)
        # This suite exercises orchestration; the supplement's byte guards have
        # their own tests. Existing fixture artwork needs no optional supplement.
        (script.parent / "package_companion_supplement.py").write_text("# fixture: no optional portraits\n")
        self.script = script
        (self.root / "repo/desktop/Package.swift").parent.mkdir(parents=True, exist_ok=True)
        (self.root / "repo/desktop/Package.swift").write_text('.package(path: "../shared/ARCHiSpatial")')
        (self.root / "repo/desktop/Tests").mkdir()
        shared = self.root / "repo/shared/ARCHiSpatial"
        (shared / "Sources").mkdir(parents=True)
        (shared / "Tests").mkdir()
        (shared / "Package.swift").write_text("// fixture local package")
        (shared / "Sources/Fixture.swift").write_text("// fixture dependency")
        resources = self.root / "repo/desktop/Sources/ARCHiDesktop/Resources"
        for name in ["CompanionArt/archi-pearl-study-v1.png", "Branding/AppIcon.icns", "ReactorBridge/worker.py",
                     "ARC3Bridge/archi_arc3_bridge.py", "RecordReader/fixture.json"]:
            target = resources / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"synthetic fixture resource")
        # Exercise the actual artwork guard with exact retained PNGs, without
        # reading any installed bundle or substituting a permissive validator.
        for name in ("hampton-liminal-seed-v1.png", "hampton-liminal-garnet-v1.png"):
            shutil.copyfile(SCRIPT.parent.parent / "desktop/Sources/ARCHiDesktop/Resources/CompanionArt" / name,
                            resources / "CompanionArt" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "ARCHiDesktop").write_bytes(b"synthetic native program")
        self.player = self.root / "Qualified Fixture.app"
        (self.player / "Contents").mkdir(parents=True)
        (self.player / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "local.archi.unityport", "ARCHiNativePresentationProtocol": 1,
            "ARCHiNativeStaffRecipeVersion": 1, "ARCHiNativeArenaProtocol": 1, "ARCHiSeedAppearanceVersion": 1,
            "ARCHiLiminalPointAssetVersion": 4,
        }))
        # Keep these orchestration tests independent of installed app resources.
        # The real finish validator has its own bounded binary tests.
        self.base = self.root / "qualified-base"
        self.base.mkdir()
        (self.base / "manifest.json").write_text('{"synthetic": true}')
        self.qualification = self.root / "qualification.json"
        self.qualification.write_text('{"synthetic": true}')
        self.representation = self.root / "representation"
        self.representation.mkdir()
        copy_resource = "import pathlib,shutil,sys\nshutil.copytree(sys.argv[1],sys.argv[2])\n"
        for name in ("package_record_reader.py", "package_representation_runtime.py"):
            (script.parent / name).write_text(copy_resource)
        (script.parent / "package_liminal_v008.py").write_text('''import pathlib,shutil,sys
allow_finish="--allow-finish" in sys.argv
allow_light="--allow-light" in sys.argv
assert not allow_light or allow_finish
for flag in ("--allow-finish", "--allow-light"):
    if flag in sys.argv: sys.argv.remove(flag)
source=pathlib.Path(sys.argv[1])
allowed={"manifest.json"}
if allow_finish: allowed.add("finish-v11")
if allow_light: allowed.add("light-v12")
assert {p.name for p in source.iterdir()} <= allowed, "assembled source requires explicit selection"
for root in sys.argv[3:5]:
    target=pathlib.Path(root)/"LiminalV008"
    if target.exists():
        assert sorted(p.name for p in target.iterdir()) == ["manifest.json"], "base validator must not see finish or light"
    else: shutil.copytree(source,target)
''')
        (script.parent / "package_liminal_finish.py").write_text('''import pathlib,plistlib,shutil,sys
allow_light="--allow-light" in sys.argv
if allow_light: sys.argv.remove("--allow-light")
mode,finish,source=sys.argv[1:4]
if mode == "check-player":
    player=pathlib.Path(sys.argv[4]); info=plistlib.loads((player/"Contents/Info.plist").read_bytes())
    assert info.get("ARCHiLiminalPointAssetVersion") == (7 if allow_light else 6)
    assert info.get("ARCHiLiminalPointFinishSHA256") == "a"*64
    assert (player/"Contents/Resources/Data/StreamingAssets/LiminalV008/finish-v11/manifest.json").is_file()
else:
    for root in sys.argv[4:6]:
        target=pathlib.Path(root)/"LiminalV008/finish-v11"
        if not target.exists(): shutil.copytree(finish,target)
        assert (target/"annotations.bin").read_bytes() == (pathlib.Path(finish)/"annotations.bin").read_bytes()
print("a"*64)
''')
        (script.parent / "package_liminal_light.py").write_text('''import pathlib,plistlib,shutil,sys
mode,light,source,finish=sys.argv[1:5]
if mode == "check-player":
    player=pathlib.Path(sys.argv[5]); info=plistlib.loads((player/"Contents/Info.plist").read_bytes())
    assert info.get("ARCHiLiminalPointAssetVersion") == 7
    assert info.get("ARCHiLiminalPointLightStyle") == "liminal-light-flow/v12"
    assert info.get("ARCHiLiminalPointLightSHA256") == "b"*64
    assert (player/"Contents/Resources/Data/StreamingAssets/LiminalV008/light-v12/manifest.json").is_file()
else:
    for root in sys.argv[5:7]:
        target=pathlib.Path(root)/"LiminalV008"
        assert (target/"finish-v11/manifest.json").is_file()
        if not (target/"light-v12").exists(): shutil.copytree(light,target/"light-v12")
        assert (target/"light-v12/curves.json").read_bytes() == (pathlib.Path(light)/"curves.json").read_bytes()
print("b"*64)
''')
        tools = self.root / "tools"
        tools.mkdir()
        for name in ["swift", "pgrep", "ps", "plutil", "codesign", "xattr", "open", "mv"]:
            target = tools / name
            target.write_text(FAKE_TOOL)
            target.chmod(0o755)
        self.trace = self.root / "commands.jsonl"
        self.env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                    "ARCHI_TEST_TRACE": str(self.trace), "ARCHI_TEST_BIN": str(self.bin),
                    "ARCHI_BUILD_SCRATCH_PATH": str(self.root / "scratch"),
                    "ARCHI_LIMINAL_PACKAGE": str(self.base), "ARCHI_LIMINAL_QUALIFICATION": str(self.qualification),
                    "ARCHI_REPRESENTATION_RUNTIME": str(self.representation)}

    def finish_fixture(self, capability=6):
        finish = self.root / "finish-v11"
        finish.mkdir()
        (finish / "manifest.json").write_text('{"syntheticFinish": true}')
        (finish / "annotations.bin").write_bytes(b"synthetic annotations")
        target = self.player / "Contents/Resources/Data/StreamingAssets/LiminalV008"
        shutil.copytree(self.base, target)
        shutil.copytree(finish, target / "finish-v11")
        info_path = self.player / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info.update(ARCHiLiminalPointAssetVersion=capability, ARCHiLiminalPointFinishSHA256="a"*64)
        info_path.write_bytes(plistlib.dumps(info))
        return finish

    def test_finish_option_preserves_player_and_copies_both_destinations_after_base_check(self):
        finish = self.finish_fixture()
        original = {str(p.relative_to(self.player)): p.read_bytes() for p in self.player.rglob("*") if p.is_file()}
        stage = self.root / "finish-review"
        result = self.run_script("--stage-only", "--stage-dir", stage, "--liminal-finish", finish)
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = stage / "ARCHi.app/Contents/Resources"
        for target in (resources / "LiminalV008/finish-v11",
                       resources / "UnityCompanion.app/Contents/Resources/Data/StreamingAssets/LiminalV008/finish-v11"):
            self.assertEqual((target / "annotations.bin").read_bytes(), b"synthetic annotations")
        self.assertEqual(original, {str(p.relative_to(self.player)): p.read_bytes() for p in self.player.rglob("*") if p.is_file()})
        info = plistlib.loads((stage / "ARCHi.app/Contents/Info.plist").read_bytes())
        self.assertEqual(info["ARCHiLiminalPointFinishSHA256"], "a"*64)
        self.assertNotIn("open", [json.loads(line)[0] for line in self.trace.read_text().splitlines()])

    def test_finish_requires_capability_six_before_build(self):
        finish = self.finish_fixture(capability=5)
        result = self.run_script("--stage-only", "--stage-dir", self.root / "wrong-capability", "--liminal-finish", finish)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("swift", [json.loads(line)[0] for line in self.trace.read_text().splitlines()])

    def test_light_option_preserves_assembled_source_and_repackages_only_generated_clone(self):
        finish = self.finish_fixture(capability=7)
        light = self.root / "light-v12"; light.mkdir()
        (light / "manifest.json").write_text('{"syntheticLight": true}')
        (light / "curves.json").write_bytes(b"synthetic curves")
        shutil.copytree(light, self.player / "Contents/Resources/Data/StreamingAssets/LiminalV008/light-v12")
        plist = self.player / "Contents/Info.plist"; info = plistlib.loads(plist.read_bytes())
        info.update(ARCHiLiminalPointLightStyle="liminal-light-flow/v12", ARCHiLiminalPointLightSHA256="b" * 64)
        plist.write_bytes(plistlib.dumps(info))
        shutil.copytree(finish, self.base / "finish-v11")
        shutil.copytree(light, self.base / "light-v12")
        source_before = {p.relative_to(self.base): p.read_bytes() for p in self.base.rglob("*") if p.is_file()}
        before = {str(p.relative_to(self.player)): p.read_bytes() for p in self.player.rglob("*") if p.is_file()}
        stage = self.root / "light-review"
        result = self.run_script("--stage-only", "--stage-dir", stage, "--liminal-finish", finish, "--liminal-light", light)
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = stage / "ARCHi.app/Contents/Resources"
        for target in (resources / "LiminalV008/light-v12", resources / "UnityCompanion.app/Contents/Resources/Data/StreamingAssets/LiminalV008/light-v12"):
            self.assertEqual((target / "curves.json").read_bytes(), b"synthetic curves")
        self.assertEqual(before, {str(p.relative_to(self.player)): p.read_bytes() for p in self.player.rglob("*") if p.is_file()})
        self.assertEqual(source_before, {p.relative_to(self.base): p.read_bytes() for p in self.base.rglob("*") if p.is_file()})
        installed_info = plistlib.loads((stage / "ARCHi.app/Contents/Info.plist").read_bytes())
        self.assertEqual(installed_info["ARCHiLiminalPointLightStyle"], "liminal-light-flow/v12")
        self.assertEqual(installed_info["ARCHiLiminalPointLightSHA256"], "b" * 64)

    def test_light_requires_explicit_finish_before_any_build(self):
        result = self.run_script("--stage-only", "--liminal-light", self.root / "light")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.trace.exists())

    def test_six_requires_explicit_finish_and_five_remains_compatible(self):
        self.finish_fixture()
        result = self.run_script("--stage-only", "--stage-dir", self.root / "no-selection")
        self.assertEqual(result.returncode, 2, result.stderr)
        info_path = self.player / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["ARCHiLiminalPointAssetVersion"] = 5
        info_path.write_bytes(plistlib.dumps(info))
        shutil.rmtree(self.player / "Contents/Resources")
        result = self.run_script("--stage-only", "--stage-dir", self.root / "legacy-five")
        self.assertEqual(result.returncode, 0, result.stderr)

    def run_script(self, *arguments, extra_env=None):
        return subprocess.run(["/bin/bash", str(self.script), *map(str, arguments), "--unity-player", str(self.player)], env={**self.env, **(extra_env or {})},
                              capture_output=True, text=True, timeout=15)

    def test_new_absolute_stage_is_packaged_without_launch_or_install(self):
        stage = self.root / "task review"
        result = self.run_script("--stage-dir", stage, "--stage-only", "--review")
        self.assertEqual(result.returncode, 0, result.stderr)
        app = stage / "ARCHi.app"
        self.assertEqual((app / "Contents/MacOS/ARCHiDesktop").read_bytes(), b"synthetic native program")
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.quotient.archi.desktop.review")
        self.assertEqual(info["ARCHiReactorPython"], str(app.resolve() / "Contents/Resources/ReactorRuntime/bin/python3"))
        self.assertEqual(stage.stat().st_mode & 0o777, 0o700)
        self.assertNotIn("open", [json.loads(line)[0] for line in self.trace.read_text().splitlines()])
        self.assertEqual(sorted(p.name for p in stage.iterdir()), ["ARCHi.app"])

    def test_identity_is_bound_after_packaging_before_signing_and_promotion(self):
        stage = self.root / "identity-review"
        result = self.run_script("--stage-only", "--stage-dir", stage)
        self.assertEqual(result.returncode, 0, result.stderr)
        app = stage / "ARCHi.app"
        receipt = json.loads((app / "Contents/Resources/ARCHiBuildIdentity.json").read_text())
        payload = {row["path"] for row in receipt["preSignPayload"]}
        self.assertIn("Contents/MacOS/ARCHiDesktop", payload)
        self.assertIn("Contents/Resources/UnityCompanion.app/Contents/Info.plist", payload)
        self.assertIn("Contents/Resources/LiminalV008/manifest.json", payload)
        self.assertNotIn("Contents/Resources/ARCHiBuildIdentity.json", payload)
        events = [json.loads(line) for line in self.trace.read_text().splitlines()]
        sign = next(i for i, event in enumerate(events) if event[0] == "identity-observed-at-outer-sign")
        build = next(i for i, event in enumerate(events) if event[:2] == ["swift", "build"])
        promote = next(i for i, event in enumerate(events) if event[0] == "mv")
        self.assertLess(build, sign)
        self.assertLess(sign, promote)

    def test_source_change_during_build_stops_before_outer_sign_or_promotion(self):
        source = self.root / "repo/shared/ARCHiSpatial/Sources/Fixture.swift"
        stage = self.root / "mutated-source-review"
        result = self.run_script("--stage-only", "--stage-dir", stage,
                                 extra_env={"ARCHI_TEST_SOURCE_MUTATION": str(source)})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inputs changed during the build", result.stderr)
        self.assertFalse((stage / "ARCHi.app").exists())
        events = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertFalse(any(event[0] in ("identity-observed-at-outer-sign", "mv", "open") for event in events))

    def test_missing_or_changed_seed_stops_before_signing_or_promotion(self):
        art = self.script.parent.parent / "desktop/Sources/ARCHiDesktop/Resources/CompanionArt"
        garnet = art / "hampton-liminal-garnet-v1.png"
        original = garnet.read_bytes()
        for mutation, error in [("missing", "Missing required path"), ("changed", "SHA-256 mismatch")]:
            with self.subTest(mutation=mutation):
                if mutation == "missing":
                    garnet.unlink()
                else:
                    garnet.write_bytes((art / "hampton-liminal-seed-v1.png").read_bytes())
                stage = self.root / ("seed-" + mutation)
                result = self.run_script("--stage-only", "--stage-dir", stage)
                self.assertEqual(result.returncode, 1, result.stderr + result.stdout)
                self.assertIn(error, result.stdout)
                self.assertFalse((stage / "ARCHi.app").exists())
                commands = [json.loads(line)[0] for line in self.trace.read_text().splitlines()]
                self.assertNotIn("codesign", commands)
                self.assertNotIn("mv", commands)
                self.assertNotIn("open", commands)
                garnet.write_bytes(original)

    def test_stage_option_requires_explicit_stage_only_absolute_path_and_argument(self):
        for arguments in [("--stage-dir",), ("--stage-dir", "--stage-only"),
                          ("--stage-dir", str(self.root / "missing-flag")),
                          ("--stage-only", "--stage-dir", "relative")]:
            with self.subTest(arguments=arguments):
                result = self.run_script(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.trace.exists(), "Validation must stop before build or process tools")

    def test_existing_directory_file_and_symlink_are_preserved_before_build(self):
        directory = self.root / "existing"
        directory.mkdir()
        (directory / "authored.txt").write_bytes(b"keep directory contents")
        file = self.root / "existing-file"
        file.write_bytes(b"keep file")
        linked = self.root / "dangling-link"
        linked.symlink_to(self.root / "absent-target")
        for target in [directory, file, linked]:
            with self.subTest(target=target):
                self.assertEqual(self.run_script("--stage-only", "--stage-dir", target).returncode, 2)
        self.assertEqual((directory / "authored.txt").read_bytes(), b"keep directory contents")
        self.assertEqual(file.read_bytes(), b"keep file")
        self.assertTrue(linked.is_symlink())
        self.assertFalse(self.trace.exists())

    def test_staging_cannot_target_application_locations_or_existing_bundle_contents(self):
        local_apps = self.root / "Applications"
        local_apps.mkdir()
        bundle = self.root / "Existing.APP"
        bundle.mkdir()
        for target in [Path("/Applications/ARCHi-stage-fixture-never-created"), local_apps / "review", bundle / "review"]:
            with self.subTest(target=target):
                self.assertEqual(self.run_script("--stage-only", "--stage-dir", target).returncode, 2)
                self.assertFalse(target.exists())
        self.assertFalse(self.trace.exists())

    def test_concurrent_destination_bundle_is_preserved_after_build(self):
        stage = self.root / "collision"
        result = self.run_script("--stage-only", "--stage-dir", stage,
                                 extra_env={"ARCHI_TEST_COLLISION": str(stage / "ARCHi.app")})
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual((stage / "ARCHi.app/authored.txt").read_text(), "preserve concurrent bundle")
        self.assertFalse((stage / "ARCHi.app/ARCHi.app").exists())
        self.assertEqual(sorted(p.name for p in stage.iterdir()), ["ARCHi.app"])

    def test_two_invocations_cannot_claim_the_same_stage_directory(self):
        stage = self.root / "single-owner"
        gate = self.root / "release-build"
        first = subprocess.Popen(["/bin/bash", str(self.script), "--stage-only", "--stage-dir", str(stage), "--unity-player", str(self.player)],
                                 env={**self.env, "ARCHI_TEST_BUILD_GATE": str(gate)}, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not stage.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(stage.is_dir())
            second = self.run_script("--stage-only", "--stage-dir", stage)
            self.assertEqual(second.returncode, 2, second.stderr)
        finally:
            gate.write_text("release synthetic build")
            stdout, stderr = first.communicate(timeout=12)
        self.assertEqual(first.returncode, 0, stdout + stderr)
        self.assertTrue((stage / "ARCHi.app/Contents/Info.plist").is_file())

    def test_bundle_appearing_at_promotion_is_not_moved_or_nested(self):
        stage = self.root / "late-collision"
        result = self.run_script("--stage-only", "--stage-dir", stage,
                                 extra_env={"ARCHI_TEST_PROMOTION_COLLISION": str(stage / "ARCHi.app")})
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual((stage / "ARCHi.app/authored.txt").read_text(), "preserve concurrent bundle")
        self.assertEqual(sorted(p.name for p in stage.iterdir()), ["ARCHi.app"])
        self.assertEqual(sorted(p.name for p in (stage / "ARCHi.app").iterdir()), ["authored.txt"])


if __name__ == "__main__":
    unittest.main()
