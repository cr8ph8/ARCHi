"""Prove metadata-only preparation and original/candidate preservation guards."""
from collections import namedtuple
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import zlib

SCRIPT_DIR = Path(__file__).resolve().parents[2] / "script"
sys.path.insert(0, str(SCRIPT_DIR))
import prepare_source_candidate as preparation


def chunk(kind, payload):
    return len(payload).to_bytes(4, "big") + kind + payload + (zlib.crc32(kind + payload) & 0xffffffff).to_bytes(4, "big")


Node = namedtuple("Node", "id props props_type elems")


class CandidatePreparationTests(unittest.TestCase):
    def test_png_keeps_idat_and_every_nonmetadata_chunk_identical(self):
        header = chunk(b"IHDR", (1).to_bytes(4, "big") * 2 + bytes([8, 6, 0, 0, 0]))
        pixels = zlib.compress(b"\0\xff\0\0\xff")
        color = chunk(b"gAMA", (45455).to_bytes(4, "big"))
        image = chunk(b"IDAT", pixels)
        end = chunk(b"IEND", b"")
        png = b"\x89PNG\r\n\x1a\n" + header + chunk(b"tEXt", b"File\0private-source") + color + chunk(b"eXIf", b"metadata") + image + end
        repaired, record = preparation.sanitize_png(png)
        self.assertEqual(repaired, png[:8] + header + color + image + end)
        self.assertEqual(record["idatSha256"], preparation.preflight.sha(pixels))
        self.assertEqual(record["scanlineSha256"], preparation.preflight.sha(zlib.decompress(pixels)))
        self.assertEqual(preparation.preflight.scan("safe.png", repaired), [])

    def test_invalid_png_never_becomes_a_candidate(self):
        with self.assertRaises(ValueError):
            preparation.sanitize_png(b"invalid")

    def test_fbx_comparison_allows_only_the_known_metadata_value(self):
        old = b"source-path"
        new = b"safe-path  "
        node = Node(b"P", [b"Original|ApplicationNativeFile", b"KString", b"", b"", old], b"SSSSS", [])
        repaired = node._replace(props=[*node.props[:-1], new])
        self.assertEqual(preparation.compare_fbx(node, repaired, old, new), 1)
        geometry = Node(b"Vertices", [[0.0, 1.0, 2.0]], b"d", [])
        changed_geometry = geometry._replace(props=[[0.0, 1.0, 3.0]])
        with self.assertRaises(ValueError):
            preparation.compare_fbx(geometry, changed_geometry, old, new)
        with self.assertRaises(ValueError):
            preparation.compare_fbx(node, node._replace(props_type=b"SSSSR"), old, new)

    def test_existing_directory_and_dangling_candidate_link_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            existing = root / "existing"
            existing.mkdir()
            with self.assertRaises(ValueError):
                preparation.prepare(root, existing, None)
            linked = root / "candidate"
            target = root / "must-not-create"
            linked.symlink_to(target, target_is_directory=True)
            with self.assertRaises(ValueError):
                preparation.prepare(root, linked, None)
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
