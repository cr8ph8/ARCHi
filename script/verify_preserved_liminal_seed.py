#!/usr/bin/env python3
"""Read-only checks for the retained Liminal Seed sources or a packaged app.

This verifies preservation and packaging, not renderer selection or visual
acceptance. It never launches an app, reads a profile, or repairs a file.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import zlib


SOURCE_ROOT = Path(__file__).resolve().parents[1]
PNG_PINS = {
    "hampton-liminal-seed-v1.png": "9ffb19a74959c29fd1ff46848937c2745c08b543b0c70871e99c4c5c606916a1",
    "hampton-liminal-garnet-v1.png": "6a60509d41e00d8dd6b204dd894b988498b6e38dabbc29349db058046e7228d0",
}
SOURCE_ART = Path("desktop/Sources/ARCHiDesktop/Resources/CompanionArt")
APP_ART = Path("Contents/Resources/CompanionArt")
BLEND_PINS = {
    "desktop/ArtSources/hampton-liminal-garnet-v1/source.blend":
        "bb199ed2d206f3b73bc9d12c0bc4f839f46862c17801342e4e547dd04061dc0f",
    "desktop/ArtSources/liminal-golden-core-v9/liminal-golden-core.blend":
        "9693ffa768bea76bc1849a0944558179f41da2c7ebf3f73ecffa279c089b3f6d",
}


def require_regular_path(path):
    """Reject symlinks in the file and every ancestor, including the app root."""
    path = Path(os.path.abspath(path))
    current = Path(path.anchor)
    for index, part in enumerate(path.parts[1:]):
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError as error:
            raise ValueError(f"Missing required path: {current}") from error
        if stat.S_ISLNK(mode):
            raise ValueError(f"Symbolic-link path component is not allowed: {current}")
        final = index == len(path.parts) - 2
        if final and not stat.S_ISREG(mode):
            raise ValueError(f"Expected a regular file: {current}")
        if not final and not stat.S_ISDIR(mode):
            raise ValueError(f"Expected a regular directory: {current}")
    return path


def png_dimensions(header):
    """Read the authenticated PNG's IHDR without needing an image library."""
    if (len(header) < 33 or header[:8] != b"\x89PNG\r\n\x1a\n"
            or header[8:16] != b"\x00\x00\x00\x0dIHDR"):
        raise ValueError("Invalid PNG signature or IHDR")
    expected_crc = struct.unpack(">I", header[29:33])[0]
    if zlib.crc32(header[12:29]) & 0xffffffff != expected_crc:
        raise ValueError("Invalid PNG IHDR checksum")
    dimensions = struct.unpack(">II", header[16:24])
    if dimensions != (512, 512):
        raise ValueError(f"Expected PNG dimensions 512x512, found {dimensions[0]}x{dimensions[1]}")
    return dimensions


def verify_file(root, relative_path, expected_digest, is_png):
    record = {"path": str(relative_path), "expectedSHA256": expected_digest, "passed": False}
    try:
        path = require_regular_path(root / relative_path)
        digest = hashlib.sha256()
        byte_count = 0
        with path.open("rb") as stream:
            header = stream.read(33)
            digest.update(header)
            byte_count += len(header)
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
                byte_count += len(chunk)
        record.update(sha256=digest.hexdigest(), bytes=byte_count)
        if is_png:
            record["dimensions"] = list(png_dimensions(header))
        if record["sha256"] != expected_digest:
            raise ValueError("SHA-256 mismatch: asset differs from the preserved source")
        # Recheck the path after reading; no linked replacement may qualify.
        require_regular_path(path)
        record["passed"] = True
    except (OSError, ValueError) as error:
        record["error"] = str(error)
    return record


def verify(root, *, app=False):
    root = Path(os.path.abspath(Path(root).expanduser()))
    art = APP_ART if app else SOURCE_ART
    records = [verify_file(root, art / name, digest, True) for name, digest in PNG_PINS.items()]
    if not app:
        records.extend(verify_file(root, Path(name), digest, False) for name, digest in BLEND_PINS.items())
    return {
        "schema": "archi-preserved-liminal-seed/v1",
        "mode": "app" if app else "source",
        "root": str(root),
        "passed": all(record["passed"] for record in records),
        "checks": records,
        "limits": "Checks retained asset bytes and paths only; does not establish active rendering, identity, or visual acceptance.",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Check the two required Seed PNGs inside this app bundle")
    args = parser.parse_args(argv)
    report = verify(args.app if args.app is not None else SOURCE_ROOT, app=args.app is not None)
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
