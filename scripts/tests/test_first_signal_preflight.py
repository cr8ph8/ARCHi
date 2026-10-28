"""Synthetic preservation checks. No real profile, compiler, game or installer."""
import importlib.util
import json
from pathlib import Path
import os
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("first_signal_preflight", ROOT / "script/first_signal_preflight.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class FirstSignalPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="first-signal-preservation-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "repo"
        host = self.repo / guard.HOST
        host.parent.mkdir(parents=True)
        shutil.copyfile(ROOT / guard.HOST, host)
        self.installed = self.root / "Applications/ARCHi.app"
        self.app(self.installed)
        self.bundled = self.installed / guard.CHAPTER
        self.chapter(self.bundled)
        self.selection = self.root / "selection.json"
        self.set_selection()
        self.plan_path = self.root / "plan.json"
        self.candidate = self.root / "candidate/ARCHi.app"
        self.app(self.candidate)
        # The three save owners are deliberately distinct. Neither copy nor
        # receipt construction may read, rewrite or combine any of these paths.
        self.saves = {}
        for name, data in {
            "native/preferences.json": b'{"version":10,"fixture":"native"}',
            "retained-practice/roster.json": b'{"version":1,"fixture":"rules-v1"}',
            "WebKit/A4A19A25/127.0.0.1-8767/localstorage": b"synthetic First Signal journey",
            "earlier-adventure/campaign.save": b"synthetic standalone campaign",
        }.items():
            path = self.root / "private-save-owners" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            self.saves[path] = data

    def app(self, path):
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/Resources").mkdir()
        (path / "Contents/MacOS/ARCHiDesktop").write_bytes(b"synthetic executable")
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": guard.OWNER["appIdentifier"], "CFBundleExecutable": "ARCHiDesktop",
            "CFBundlePackageType": "APPL"}))

    def chapter(self, path):
        (path / "assets").mkdir(parents=True)
        (path / "qimon-build.json").write_text(json.dumps({"schema": 1, "game": "qimon-first-signal", "entry": "index.html"}))
        (path / "index.html").write_text('<!doctype html><script src="assets/chapter.js"></script>')
        (path / "assets/chapter.js").write_bytes(b"// synthetic chapter, never executed")
        (path / "assets/portrait.png").write_bytes(b"synthetic image bytes")

    def set_selection(self, path=None, *, stale=False, earlier=None):
        def entry(location):
            return {"present": True, "stale": stale, "sha256": "a" * 64, "path": str(location)} if location else {"present": False}
        self.selection.write_text(json.dumps({"schema": "archi-first-signal-selection/v1", "owner": guard.OWNER,
                                             "chapter": entry(path), "earlierAdventure": entry(earlier)}))

    def capture(self, **kwargs):
        return guard.capture(self.repo, self.installed, self.selection, self.plan_path, **kwargs)

    def package(self, plan):
        guard.package(plan, self.repo, self.selection, self.candidate)

    def verify(self, plan):
        guard.verify(plan, self.repo, self.selection, self.candidate)

    def assert_saves_unchanged(self):
        for path, data in self.saves.items():
            self.assertEqual(path.read_bytes(), data)

    def test_bundled_chapter_is_copied_exactly_without_touching_any_save_owner(self):
        original = guard.resources(self.bundled)
        plan = self.capture()
        self.package(plan)
        self.verify(plan)
        self.assertEqual(original, guard.resources(self.candidate / guard.CHAPTER))
        self.assertEqual(original, guard.resources(self.bundled))
        receipt = guard.load(self.candidate / guard.RECEIPT)
        self.assertEqual(receipt["owner"], guard.OWNER)
        self.assertEqual(receipt["status"], "PRESERVED_BYTES_ONLY")
        self.assertNotIn(str(self.root), json.dumps(receipt))
        self.assert_saves_unchanged()

    def test_missing_chapter_cannot_be_inferred_from_native_or_retained_game_source(self):
        shutil.rmtree(self.bundled)
        retained = self.repo / "dist"
        self.chapter(retained)
        with self.assertRaisesRegex(ValueError, "No preserved"):
            self.capture()
        self.assertFalse(self.plan_path.exists())
        self.assertFalse((self.candidate / guard.CHAPTER).exists())
        self.assert_saves_unchanged()

    def test_adjacent_build_is_bundled_without_moving_the_original(self):
        adjacent = self.installed.parent / "QiMonFirstSignalWeb"
        self.bundled.rename(adjacent)
        plan = self.capture()
        self.package(plan)
        self.verify(plan)
        self.assertEqual(guard.resources(adjacent), guard.resources(self.candidate / guard.CHAPTER))

    def test_external_selection_and_its_bookmark_are_preserved(self):
        external = self.root / "authored game"
        shutil.copytree(self.bundled, external)
        self.set_selection(external)
        before = self.selection.read_bytes()
        plan = self.capture()
        self.assertEqual(plan["source"], str(external))
        self.package(plan)
        self.verify(plan)
        self.assertEqual(self.selection.read_bytes(), before)
        self.assertEqual(guard.resources(external), plan["resources"])
        self.assert_saves_unchanged()

    def test_invalid_or_stale_explicit_selection_never_falls_back_to_bundled_build(self):
        for stale, path in [(False, self.root / "missing"), (True, self.bundled)]:
            with self.subTest(stale=stale):
                self.set_selection(path, stale=stale)
                with self.assertRaises((ValueError, FileNotFoundError)):
                    self.capture()
                self.assertFalse(self.plan_path.exists())

    def test_bookmark_into_any_old_bundle_folder_is_a_blocker(self):
        alternate = self.installed / "Contents/Resources/AlternateChapter"
        shutil.copytree(self.bundled, alternate)
        for path in (self.bundled, alternate):
            with self.subTest(path=path):
                self.set_selection(path)
                with self.assertRaisesRegex(ValueError, "inside the installed app"):
                    self.capture()

    def test_divergent_discovery_candidates_are_not_silently_chosen(self):
        adjacent = self.installed.parent / "QiMonFirstSignalWeb"
        shutil.copytree(self.bundled, adjacent)
        (adjacent / "assets/chapter.js").write_bytes(b"a different chapter")
        with self.assertRaisesRegex(ValueError, "resource mismatch"):
            self.capture()

    def test_explicit_build_requires_an_independent_manifest_and_matching_existing_chapter(self):
        external = self.root / "verified build"
        shutil.copytree(self.bundled, external)
        with self.assertRaisesRegex(ValueError, "both"):
            self.capture(build=external)
        manifest = self.root / "independent-manifest.json"
        guard.write_new(manifest, guard.resources(external))
        (external / "assets/chapter.js").unlink()  # Host marker/entry alone still pass discovery.
        with self.assertRaisesRegex(ValueError, "independent manifest"):
            self.capture(build=external, manifest=manifest)
        manifest.unlink()
        guard.write_new(manifest, guard.resources(external))
        with self.assertRaisesRegex(ValueError, "resource mismatch"):
            self.capture(build=external, manifest=manifest)

    def test_first_install_requires_a_verified_explicit_build(self):
        external = self.root / "verified"
        self.bundled.rename(external)
        shutil.rmtree(self.installed)
        self.set_selection(external)
        with self.assertRaisesRegex(ValueError, "No preserved"):
            self.capture()
        manifest = self.root / "reference.json"
        guard.write_new(manifest, guard.resources(external))
        plan = self.capture(build=external, manifest=manifest)
        self.package(plan)
        self.verify(plan)

    def test_chapter_change_after_capture_stops_before_copy(self):
        plan = self.capture()
        (self.bundled / "assets/chapter.js").write_bytes(b"concurrent source change")
        with self.assertRaisesRegex(ValueError, "resources changed"):
            self.package(plan)
        self.assertFalse((self.candidate / guard.CHAPTER).exists())

    def test_new_discovery_candidate_during_build_is_a_blocker(self):
        plan = self.capture()
        shutil.copytree(self.bundled, self.installed.parent / "QiMonFirstSignalWeb")
        with self.assertRaisesRegex(ValueError, "appeared"):
            self.package(plan)

    def test_failed_staging_preserves_old_app_and_all_save_owners(self):
        plan = self.capture()
        before = guard.installed_identity(self.installed)
        with patch.object(guard.shutil, "copytree", side_effect=OSError("fixture: disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                self.package(plan)
        self.assertEqual(before, guard.installed_identity(self.installed))
        self.assertFalse((self.candidate / guard.RECEIPT).exists())
        self.assert_saves_unchanged()

    def test_corruption_in_copied_chapter_is_rejected_before_receipt(self):
        plan = self.capture()
        copy = shutil.copytree
        def corrupt(*args, **kwargs):
            result = copy(*args, **kwargs)
            (Path(args[1]) / "index.html").write_bytes(b"broken copy")
            return result
        with patch.object(guard.shutil, "copytree", side_effect=corrupt):
            with self.assertRaisesRegex(ValueError, "copy does not match"):
                self.package(plan)
        self.assertFalse((self.candidate / guard.RECEIPT).exists())
        self.assert_saves_unchanged()

    def test_source_change_during_copy_is_rejected(self):
        plan = self.capture()
        copy = shutil.copytree
        def mutate(*args, **kwargs):
            result = copy(*args, **kwargs)
            (self.bundled / "index.html").write_bytes(b"changed after copy")
            return result
        with patch.object(guard.shutil, "copytree", side_effect=mutate):
            with self.assertRaisesRegex(ValueError, "resources changed"):
                self.package(plan)
        self.assertFalse((self.candidate / guard.RECEIPT).exists())

    def test_final_verification_rejects_changed_candidate_resources_and_owner(self):
        plan = self.capture()
        self.package(plan)
        entry = self.candidate / guard.CHAPTER / "index.html"
        original = entry.read_bytes()
        entry.write_bytes(b"changed on destination filesystem")
        with self.assertRaisesRegex(ValueError, "resources/receipt changed"):
            self.verify(plan)
        entry.write_bytes(original)
        plist = self.candidate / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info["CFBundleIdentifier"] = "different.empty.profile"
        plist.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "disconnect"):
            self.verify(plan)
        self.assert_saves_unchanged()

    def test_final_verification_rejects_selection_or_installed_binary_changes(self):
        plan = self.capture()
        self.package(plan)
        self.set_selection(self.bundled)
        with self.assertRaisesRegex(ValueError, "selected save owner changed"):
            self.verify(plan)
        self.set_selection()
        (self.installed / "Contents/MacOS/ARCHiDesktop").write_bytes(b"another installer ran")
        with self.assertRaisesRegex(ValueError, "Installed app changed"):
            self.verify(plan)

    def test_changed_origin_datastore_save_key_or_defaults_suite_requires_review(self):
        host = self.repo / guard.HOST
        text = host.read_text()
        for old in ["127.0.0.1:8767", guard.OWNER["dataStoreID"], guard.OWNER["saveKey"],
                    guard.OWNER["defaultsSuite"], guard.OWNER["selectionKey"]]:
            with self.subTest(pin=old):
                host.write_text(text.replace(old, "changed-owner"))
                with self.assertRaisesRegex(ValueError, "owner changed"):
                    self.capture()
        host.write_text(text)

    def test_incomplete_wrong_and_oversized_marker_or_entry_are_blockers(self):
        marker = self.bundled / "qimon-build.json"
        for value in [b"{}", b'{"schema":true,"game":"qimon-first-signal","entry":"index.html"}', b" " * 4097]:
            with self.subTest(value=value[:30]):
                marker.write_bytes(value)
                with self.assertRaises(ValueError):
                    self.capture()
        marker.unlink()
        with self.assertRaisesRegex(ValueError, "marker/entry"):
            self.capture()

    def test_links_hidden_and_special_resources_require_review(self):
        extra = self.bundled / "assets/extra"
        extra.symlink_to(self.selection)
        with self.assertRaisesRegex(ValueError, "linked"):
            self.capture()
        extra.unlink()
        os.mkfifo(extra)
        with self.assertRaisesRegex(ValueError, "Special"):
            self.capture()
        extra.unlink()
        (self.bundled / ".env").write_bytes(b"synthetic private build config")
        with self.assertRaisesRegex(ValueError, "Hidden"):
            self.capture()

    def test_earlier_bundled_adventure_blocks_a_web_only_replacement(self):
        (self.installed / "Contents/Resources/QiMon First Signal.app").mkdir()
        with self.assertRaisesRegex(ValueError, "earlier adventure"):
            self.capture()
        self.assert_saves_unchanged()

    def test_existing_candidate_chapter_and_evidence_files_are_never_overwritten(self):
        plan = self.capture()
        self.package(plan)
        with self.assertRaises(FileExistsError):
            self.package(plan)
        with self.assertRaises(FileExistsError):
            self.capture()

    def test_swift_inspector_and_python_guard_use_the_same_owner_pins(self):
        inspector = (ROOT / "script/inspect_first_signal_selection.swift").read_text()
        for value in guard.OWNER.values():
            self.assertIn('"' + value + '"', inspector)
        self.assertNotIn("defaults.set(", inspector)
        self.assertNotIn("WKWebView", inspector)


if __name__ == "__main__":
    unittest.main()
