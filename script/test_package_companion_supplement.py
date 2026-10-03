#!/usr/bin/env python3
"""Bounded supplemental-art packaging checks; synthetic bytes only."""
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

import package_companion_supplement as subject


class CompanionSupplementTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir="/private/tmp")
        self.root = Path(self.temp.name)
        self.destination = self.root / "generated"
        self.source = self.root / "source"
        self.installed = self.root / "installed"
        for folder in [self.destination, self.source, self.installed]:
            folder.mkdir()
        self.payloads = {}
        approved = {}
        fields = []
        for index, (name, (key, _)) in enumerate(subject.APPROVED.items()):
            payload = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 512, 512) + bytes([index]) * 9
            self.payloads[name] = payload
            digest = hashlib.sha256(payload).hexdigest()
            approved[name] = (key, digest)
            fields += [f'static let {key}Filename = "{name[:-4]}"', f'static let {key}Digest = "{digest}"']
        self.contract = patch.object(subject, "APPROVED", approved)
        self.contract.start()
        self.loader = self.root / "loader.swift"
        self.loader.write_text("\n".join(fields))
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.contract.stop)

    def fill(self, folder):
        for name, payload in self.payloads.items():
            (folder / name).write_bytes(payload)

    def package(self, explicit=False):
        return subject.package(self.destination, source=self.source if explicit else None,
                               installed=self.installed, loader=self.loader)

    def test_explicit_source_copies_only_exact_allowlist_without_mutating_source(self):
        self.fill(self.source)
        (self.source / "private-notes.txt").write_text("excluded")
        before = {p.name: p.read_bytes() for p in self.source.iterdir()}
        result = self.package(True)
        self.assertEqual(set(result["copied"]), set(self.payloads))
        self.assertEqual({p.name: p.read_bytes() for p in self.destination.iterdir()}, self.payloads)
        self.assertEqual({p.name: p.read_bytes() for p in self.source.iterdir()}, before)

    def test_default_preserves_exact_installed_art(self):
        self.fill(self.installed)
        self.assertEqual(set(self.package()["copied"]), set(self.payloads))
        self.assertEqual({p.name: p.read_bytes() for p in self.installed.iterdir()}, self.payloads)

    def test_correct_destination_takes_precedence_over_default_source(self):
        self.fill(self.destination)
        for name in self.payloads:
            (self.installed / name).write_text("bad old copy")
        self.assertEqual(set(self.package()["retained"]), set(self.payloads))

    def test_missing_default_is_explicitly_unavailable(self):
        self.assertEqual(set(self.package()["unavailable"]), set(self.payloads))
        self.assertEqual(list(self.destination.iterdir()), [])
        self.installed.rmdir()
        self.assertEqual(set(self.package()["unavailable"]), set(self.payloads))

    def test_explicit_missing_fails_even_if_destination_is_present(self):
        self.fill(self.destination)
        with self.assertRaises(ValueError): self.package(True)

    def test_mismatched_explicit_source_fails_before_any_copy(self):
        self.fill(self.source)
        (self.source / list(self.payloads)[1]).write_text("wrong")
        with self.assertRaises(ValueError): self.package(True)
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_mismatched_default_source_fails_before_any_copy(self):
        self.fill(self.installed)
        (self.installed / list(self.payloads)[1]).write_text("wrong")
        with self.assertRaises(ValueError): self.package()
        self.assertEqual(list(self.destination.iterdir()), [])

    def test_mismatched_destination_is_never_replaced(self):
        self.fill(self.source)
        target = self.destination / next(iter(self.payloads))
        target.write_bytes(b"authored wrong bytes")
        with self.assertRaises(ValueError): self.package(True)
        self.assertEqual(target.read_bytes(), b"authored wrong bytes")

    def test_symlink_leaf_and_parent_are_rejected(self):
        self.fill(self.source)
        name = next(iter(self.payloads))
        (self.source / name).unlink()
        (self.source / name).symlink_to(self.loader)
        with self.assertRaises(ValueError): self.package(True)
        alias = self.root / "alias"
        alias.symlink_to(self.source, target_is_directory=True)
        with self.assertRaises(ValueError):
            subject.package(self.destination, source=alias, loader=self.loader)

    def test_destination_symlink_is_rejected(self):
        self.fill(self.source)
        name = next(iter(self.payloads))
        (self.destination / name).symlink_to(self.source / name)
        with self.assertRaises(ValueError): self.package(True)

    def test_loader_pin_drift_or_duplicates_fail(self):
        original = self.loader.read_text()
        self.loader.write_text(original.replace("Digest =", 'DigestX =', 1))
        with self.assertRaises(ValueError): self.package()
        self.loader.write_text(original + "\n" + original.splitlines()[0])
        with self.assertRaises(ValueError): self.package()

    def test_bounds_and_nonregular_files_rejected(self):
        self.fill(self.source)
        target = self.source / next(iter(self.payloads))
        target.write_bytes(b"x" * subject.MAXIMUM_BYTES)
        with self.assertRaises(ValueError): self.package(True)
        target.unlink(); target.mkdir()
        with self.assertRaises(ValueError): self.package(True)

    def test_source_destination_overlap_rejected(self):
        self.fill(self.source)
        with self.assertRaises(ValueError):
            subject.package(self.source, source=self.source, loader=self.loader)

    def test_relative_or_parent_traversal_paths_rejected(self):
        with self.assertRaises(ValueError): subject.checked_path(Path("relative"))
        with self.assertRaises(ValueError): subject.checked_path(self.root / "source" / "..")


if __name__ == "__main__":
    unittest.main()
