#!/usr/bin/env python3
"""Focused rollback reservation checks. All bundle and home paths are fixtures."""

from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
from unittest.mock import patch

from app_rollback_destination import reserve_rollback_destination


IDENTIFIER = "com.quotient.archi.desktop.review"


class RollbackDestinationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.app = self.root / "Applications" / "ARCHi.app"
        (self.app / "Contents").mkdir(parents=True)
        self.plist = self.app / "Contents" / "Info.plist"
        self.write_identity(IDENTIFIER)
        self.rollbacks = self.home / "Library" / "Application Support" / "ARCHiRecovery" / "Rollbacks"

    def write_identity(self, identifier, package_type="APPL"):
        self.plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier, "CFBundlePackageType": package_type}))

    def reserve(self):
        return reserve_rollback_destination(self.app, IDENTIFIER, self.home)

    def test_reserves_unique_private_same_filesystem_paths_without_moving_app(self):
        first, second = self.reserve(), self.reserve()
        self.assertNotEqual(first, second)
        self.assertEqual(first.name, "ARCHi.app")
        self.assertEqual(first.parent.parent, self.rollbacks)
        self.assertFalse(first.exists())
        self.assertTrue(self.plist.is_file())
        for directory in (self.rollbacks.parent, self.rollbacks, first.parent, second.parent):
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
            self.assertEqual(directory.stat().st_dev, self.app.parent.stat().st_dev)

    def test_rejects_wrong_bundle_identity(self):
        self.write_identity("com.example.other")
        with self.assertRaisesRegex(ValueError, "identity"):
            self.reserve()
        self.assertFalse(self.rollbacks.exists())
        self.assertTrue(self.plist.exists())

    def test_rejects_non_application_package(self):
        self.write_identity(IDENTIFIER, "BNDL")
        with self.assertRaisesRegex(ValueError, "identity"):
            self.reserve()

    def test_rejects_invalid_plist(self):
        self.plist.write_bytes(b"not a plist")
        with self.assertRaises(plistlib.InvalidFileException):
            self.reserve()

    def test_rejects_symlinked_bundle(self):
        target = self.app.with_name("Original.app")
        self.app.rename(target)
        self.app.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.reserve()
        self.assertTrue(self.app.is_symlink())

    def test_rejects_symlinked_bundle_metadata(self):
        target = self.root / "identity.plist"
        self.plist.rename(target)
        self.plist.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.reserve()

    def test_rejects_symlinked_recovery_ancestor(self):
        target = self.root / "external-library"
        target.mkdir()
        (self.home / "Library").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.reserve()
        self.assertEqual(list(target.iterdir()), [])

    def test_rejects_symlinked_rollbacks(self):
        self.rollbacks.parent.mkdir(parents=True, mode=0o700)
        target = self.root / "external-rollbacks"
        target.mkdir(mode=0o700)
        self.rollbacks.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.reserve()

    def test_rejects_existing_non_private_recovery(self):
        self.rollbacks.parent.mkdir(parents=True, mode=0o755)
        with self.assertRaisesRegex(ValueError, "0700"):
            self.reserve()
        self.assertEqual(stat.S_IMODE(self.rollbacks.parent.stat().st_mode), 0o755)

    def test_rejects_unwritable_recovery(self):
        self.rollbacks.mkdir(parents=True, mode=0o700)
        self.rollbacks.parent.chmod(0o700)
        self.rollbacks.chmod(0o500)
        self.addCleanup(self.rollbacks.chmod, 0o700)
        with self.assertRaisesRegex(ValueError, "not writable"):
            self.reserve()
        self.assertTrue(self.plist.exists())

    def test_rejects_denied_write_access(self):
        with patch("app_rollback_destination.os.access", return_value=False):
            with self.assertRaisesRegex(ValueError, "not writable"):
                self.reserve()

    def test_rejects_different_filesystem(self):
        with patch("app_rollback_destination._device_id", side_effect=(1, 1, 2)):
            with self.assertRaisesRegex(ValueError, "same filesystem"):
                self.reserve()
        self.assertEqual(list(self.rollbacks.iterdir()), [])
        self.assertTrue(self.plist.exists())

    def test_rejects_app_bundle_on_a_separate_mount(self):
        with patch("app_rollback_destination._device_id", side_effect=(2, 1, 1)):
            with self.assertRaisesRegex(ValueError, "same filesystem"):
                self.reserve()


if __name__ == "__main__":
    unittest.main()
