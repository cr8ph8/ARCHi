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
    marker = os.environ.get("ARCHI_TEST_APP_OPENED")
    if marker and pathlib.Path(marker).exists():
        print("42")
        sys.exit(0)
    sys.exit(1)
if name == "ps":
    print(os.environ.get("ARCHI_TEST_RUNNING_APP", ""))
if name == "open":
    sys.exit(90)
if name == "PlistBuddy":
    key = sys.argv[2].split(":", 1)[1]
    print(plistlib.loads(pathlib.Path(sys.argv[3]).read_bytes())[key])
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
    if len(sys.argv) > 1 and sys.argv[1].endswith("inspect_first_signal_selection.swift"):
        marker = os.environ.get("ARCHI_TEST_APP_OPENED")
        if marker:
            events = [json.loads(line) for line in pathlib.Path(os.environ["ARCHI_TEST_TRACE"]).read_text().splitlines()]
            if sum(event[0] == "swift" and len(event) > 1 and event[1].endswith("inspect_first_signal_selection.swift") for event in events) == 2:
                pathlib.Path(marker).write_text("synthetic app opened during final preflight")
        print(pathlib.Path(os.environ["ARCHI_TEST_SELECTION"]).read_text())
        sys.exit(0)
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
    elif os.environ.get("ARCHI_TEST_BUILD_FAILURE"):
        sys.exit(92)
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
    if os.environ.get("ARCHI_TEST_FINAL_RESOURCE_MISMATCH"):
        (pathlib.Path(sys.argv[-1]) / "Contents/Resources/QiMonFirstSignalWeb/assets/chapter.js").write_bytes(b"corrupt final copy")
    if os.environ.get("ARCHI_TEST_STAGING_FAILURE"):
        sys.exit(93)
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
        # Absolute macOS tools and destinations are substituted only in this
        # disposable script copy. Copies/moves remain real and confined here.
        self.installed = self.root / "installed/ARCHi.app"
        self.installed.parent.mkdir()
        private_tmp = self.root / "private-tmp"
        private_tmp.mkdir()
        script = self.root / "repo/script/build_and_run.sh"
        script.parent.mkdir(parents=True)
        recipe = SCRIPT.read_text().replace('/Applications/$APP_NAME.app', str(self.installed))
        recipe = recipe.replace('/Applications/ARCHi.app', str(self.installed))
        recipe = recipe.replace('/private/tmp/', str(private_tmp) + '/')
        recipe = recipe.replace('/usr/libexec/PlistBuddy', str(self.root / 'tools/PlistBuddy'))
        recipe = recipe.replace('/bin/cp -cR', '/bin/cp -R')
        script.write_text(recipe)
        shutil.copy2(SCRIPT.parent / "verify_preserved_liminal_seed.py", script.parent)
        shutil.copy2(SCRIPT.parent / "native_build_identity.py", script.parent)
        shutil.copy2(SCRIPT.parent / "first_signal_preflight.py", script.parent)
        shutil.copy2(SCRIPT.parent / "inspect_first_signal_selection.swift", script.parent)
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
        shutil.copy2(SCRIPT.parent.parent / "desktop/Sources/ARCHiDesktop/QiMonEmbeddedGame.swift",
                     resources.parent / "QiMonEmbeddedGame.swift")
        (self.installed / "Contents/MacOS").mkdir(parents=True)
        (self.installed / "Contents/MacOS/ARCHiDesktop").write_bytes(b"working app fixture")
        (self.installed / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.quotient.archi.desktop.review", "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "ARCHiDesktop"}))
        self.chapter = self.installed / "Contents/Resources/QiMonFirstSignalWeb"
        (self.chapter / "assets").mkdir(parents=True)
        (self.chapter / "qimon-build.json").write_text('{"schema":1,"game":"qimon-first-signal","entry":"index.html"}')
        (self.chapter / "index.html").write_text('<script src="assets/chapter.js"></script>')
        (self.chapter / "assets/chapter.js").write_bytes(b"synthetic First Signal chapter")
        self.selection = self.root / "selection.json"
        self.selection.write_text(json.dumps({"schema": "archi-first-signal-selection/v1", "owner": {
            "appIdentifier": "com.quotient.archi.desktop.review", "origin": "http://127.0.0.1:8767/",
            "dataStoreID": "A4A19A25-351B-45B6-9D70-3B15D0A02817", "saveKey": "qimon.first-signal.chapter.v1",
            "defaultsSuite": "com.quotient.archi.qimon-local-play", "selectionKey": "selectedEmbeddedFolder.v1"},
            "chapter": {"present": False}, "earlierAdventure": {"present": False}}))
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
        for name in ["swift", "pgrep", "ps", "plutil", "codesign", "xattr", "open", "mv", "PlistBuddy"]:
            target = tools / name
            target.write_text(FAKE_TOOL)
            target.chmod(0o755)
        self.trace = self.root / "commands.jsonl"
        self.env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                    "ARCHI_TEST_TRACE": str(self.trace), "ARCHI_TEST_BIN": str(self.bin),
                    "ARCHI_TEST_SELECTION": str(self.selection),
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
        self.assertFalse((app / "Contents/Resources/ReactorRuntime").exists(), "An absent optional runtime stays absent")
        self.assertEqual(stage.stat().st_mode & 0o777, 0o700)
        self.assertNotIn("open", [json.loads(line)[0] for line in self.trace.read_text().splitlines()])
        self.assertEqual(sorted(p.name for p in stage.iterdir()), ["ARCHi.app"])

    def reactor_runtime_fixture(self, root, label):
        (root / "bin").mkdir(parents=True)
        (root / "bin/python3").write_bytes(b"synthetic interpreter: " + label)
        (root / "bin/python3").chmod(0o755)
        (root / "lib").mkdir()
        (root / "lib/runtime-data").write_bytes(b"synthetic runtime data: " + label)
        return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}

    def test_installed_reactor_runtime_is_preserved_in_new_stage(self):
        runtime = self.installed / "Contents/Resources/ReactorRuntime"
        expected = self.reactor_runtime_fixture(runtime, b"installed")
        stage = self.root / "reactor-preservation"
        result = self.run_script("--stage-only", "--stage-dir", stage)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        copied = stage / "ARCHi.app/Contents/Resources/ReactorRuntime"
        actual = {str(path.relative_to(copied)): path.read_bytes() for path in copied.rglob("*") if path.is_file()}
        self.assertEqual(actual, expected)
        self.assertTrue(os.access(copied / "bin/python3", os.X_OK))
        self.assertEqual({str(path.relative_to(runtime)): path.read_bytes() for path in runtime.rglob("*") if path.is_file()}, expected)
        self.assertEqual((self.installed / "Contents/MacOS/ARCHiDesktop").read_bytes(), b"working app fixture")

    def test_installed_reactor_runtime_survives_synthetic_install_and_rollback_copy(self):
        runtime = self.installed / "Contents/Resources/ReactorRuntime"
        expected = self.reactor_runtime_fixture(runtime, b"installed")
        # Use the real rollback helper, with only its home root confined to this
        # fixture. This never changes HOME or accesses the user's recovery store.
        fixture_home = self.root / "fixture-home"
        fixture_home.mkdir()
        rollback = (SCRIPT.parent / "app_rollback_destination.py").read_text()
        self.assertEqual(rollback.count("Path.home()"), 1)
        (self.script.parent / "app_rollback_destination.py").write_text(
            rollback.replace("Path.home()", f"Path({str(fixture_home)!r})"))
        result = self.run_script("--build-only")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.installed / "Contents/MacOS/ARCHiDesktop").read_bytes(), b"synthetic native program")
        self.assertEqual({str(path.relative_to(runtime)): path.read_bytes() for path in runtime.rglob("*") if path.is_file()}, expected)
        previous = list((fixture_home / "Library/Application Support/ARCHiRecovery/Rollbacks").glob("*/ARCHi.app"))
        self.assertEqual(len(previous), 1)
        self.assertEqual((previous[0] / "Contents/MacOS/ARCHiDesktop").read_bytes(), b"working app fixture")
        preserved = previous[0] / "Contents/Resources/ReactorRuntime"
        self.assertEqual({str(path.relative_to(preserved)): path.read_bytes() for path in preserved.rglob("*") if path.is_file()}, expected)
        self.assertNotIn("open", [json.loads(line)[0] for line in self.trace.read_text().splitlines()])

    def test_authoring_reactor_runtime_keeps_precedence_and_copies_launcher_by_value(self):
        installed_runtime = self.installed / "Contents/Resources/ReactorRuntime"
        original = self.reactor_runtime_fixture(installed_runtime, b"installed")
        source = self.root / "repo/output/creative-tools/reactor/runtime"
        expected = self.reactor_runtime_fixture(source, b"authoring")
        interpreter = self.root / "external-fixture-python"
        (source / "bin/python3").rename(interpreter)
        (source / "bin/python3").symlink_to(interpreter)
        stage = self.root / "reactor-authoring"
        result = self.run_script("--stage-only", "--stage-dir", stage)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        copied = stage / "ARCHi.app/Contents/Resources/ReactorRuntime"
        self.assertEqual({str(path.relative_to(copied)): path.read_bytes() for path in copied.rglob("*") if path.is_file()}, expected)
        self.assertFalse((copied / "bin/python3").is_symlink())
        self.assertTrue(os.access(copied / "bin/python3", os.X_OK))
        self.assertTrue((source / "bin/python3").is_symlink())
        self.assertEqual({str(path.relative_to(installed_runtime)): path.read_bytes() for path in installed_runtime.rglob("*") if path.is_file()}, original)

    def test_malformed_selected_reactor_runtime_blocks_promotion(self):
        installed_runtime = self.installed / "Contents/Resources/ReactorRuntime"
        source = self.root / "repo/output/creative-tools/reactor/runtime"
        before = (self.installed / "Contents/MacOS/ARCHiDesktop").read_bytes()
        for origin in ("installed", "authoring"):
            for fault in ("missing-interpreter", "non-executable", "directory-interpreter", "dangling-root"):
                with self.subTest(origin=origin, fault=fault):
                    for existing in (source, installed_runtime):
                        if existing.is_symlink():
                            existing.unlink()
                        elif existing.exists():
                            shutil.rmtree(existing)
                    selected = installed_runtime if origin == "installed" else source
                    if origin == "authoring":
                        self.reactor_runtime_fixture(installed_runtime, b"valid fallback must not hide a broken selected source")
                    selected.parent.mkdir(parents=True, exist_ok=True)
                    if fault == "dangling-root":
                        selected.symlink_to(self.root / "absent-runtime")
                    else:
                        self.reactor_runtime_fixture(selected, b"invalid")
                        interpreter = selected / "bin/python3"
                        if fault == "non-executable":
                            interpreter.chmod(0o644)
                        else:
                            interpreter.unlink()
                            if fault == "directory-interpreter":
                                interpreter.mkdir()
                    self.trace.unlink(missing_ok=True)
                    stage = self.root / (origin + "-" + fault)
                    result = self.run_script("--stage-only", "--stage-dir", stage)
                    self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                    self.assertIn("selected Reactor runtime", result.stderr)
                    self.assertFalse((stage / "ARCHi.app").exists())
                    self.assertEqual((self.installed / "Contents/MacOS/ARCHiDesktop").read_bytes(), before)
                    events = [json.loads(line)[0] for line in self.trace.read_text().splitlines()]
                    self.assertNotIn("mv", events)
                    self.assertNotIn("open", events)
                    self.assertNotIn("identity-observed-at-outer-sign", events)

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
        self.assertIn("Contents/Resources/QiMonFirstSignalWeb/assets/chapter.js", payload)
        self.assertIn("Contents/Resources/FirstSignalPreservation.json", payload)
        self.assertNotIn("Contents/Resources/ARCHiBuildIdentity.json", payload)
        events = [json.loads(line) for line in self.trace.read_text().splitlines()]
        sign = next(i for i, event in enumerate(events) if event[0] == "identity-observed-at-outer-sign")
        build = next(i for i, event in enumerate(events) if event[:2] == ["swift", "build"])
        promote = next(i for i, event in enumerate(events) if event[0] == "mv")
        self.assertLess(build, sign)
        self.assertLess(sign, promote)

    def test_missing_chapter_blocks_stage_and_build_only_before_native_build(self):
        shutil.rmtree(self.chapter)
        before = (self.installed / "Contents/MacOS/ARCHiDesktop").read_bytes()
        for flags in [("--stage-only", "--stage-dir", self.root / "missing-chapter"), ("--build-only",)]:
            with self.subTest(flags=flags):
                result = self.run_script(*flags)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("No preserved First Signal", result.stderr)
        commands = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertFalse(any(event[:2] == ["swift", "build"] or event[0] in ("mv", "open", "codesign") for event in commands))
        self.assertEqual((self.installed / "Contents/MacOS/ARCHiDesktop").read_bytes(), before)

    def test_failed_compile_or_final_staging_verification_never_promotes_or_changes_installed_chapter(self):
        before = (self.chapter / "assets/chapter.js").read_bytes()
        for failure in ("ARCHI_TEST_BUILD_FAILURE", "ARCHI_TEST_STAGING_FAILURE", "ARCHI_TEST_FINAL_RESOURCE_MISMATCH"):
            with self.subTest(failure=failure):
                self.trace.unlink(missing_ok=True)
                stage = self.root / failure
                result = self.run_script("--stage-only", "--stage-dir", stage, extra_env={failure: "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((stage / "ARCHi.app").exists())
                self.assertEqual((self.chapter / "assets/chapter.js").read_bytes(), before)
                commands = [json.loads(line)[0] for line in self.trace.read_text().splitlines()]
                self.assertNotIn("mv", commands)
                self.assertNotIn("open", commands)

    def test_first_signal_path_options_require_a_pair_before_process_or_build_tools(self):
        for flags in [("--first-signal-build",), ("--first-signal-manifest",),
                      ("--first-signal-build", str(self.chapter)), ("--first-signal-manifest", "reference.json")]:
            with self.subTest(flags=flags):
                result = self.run_script(*flags)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(self.trace.exists())

    def test_app_opened_during_final_preflight_is_rechecked_before_promotion(self):
        stage = self.root / "opened-during-preflight"
        result = self.run_script("--stage-only", "--stage-dir", stage, extra_env={
            "ARCHI_TEST_APP_OPENED": str(self.root / "synthetic-running-marker"),
            "ARCHI_TEST_RUNNING_APP": str(stage / "ARCHi.app/Contents/MacOS/ARCHiDesktop")})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ARCHi is still running", result.stderr)
        self.assertFalse((stage / "ARCHi.app").exists())
        commands = [json.loads(line)[0] for line in self.trace.read_text().splitlines()]
        self.assertNotIn("mv", commands)
        self.assertNotIn("open", commands)

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
