#!/usr/bin/env python3
"""Preserve two locally qualified companion portraits in a generated bundle.

This does not publish artwork or mutate the source/installed application. The
native loader's literal pins must still match this explicit packaging contract.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import stat
import struct
import sys

APPROVED = {
    "archi-proto-blender-v1.png": ("proto", "f64051b207446340c9e813c35e89087afc6fac068ca0d7ec38d22d86e56ac688"),
    "archi-ball-of-light-v1.png": ("lightSeed", "867b75f54b17619c9eaca563515221e5f7b5e49385b9f29cad8b5216213dd9c4"),
}
MAXIMUM_BYTES = 1_400_000  # The native loader requires strictly fewer bytes.
DEFAULT_INSTALLED = Path("/Applications/ARCHi.app/Contents/Resources/CompanionArt")
DEFAULT_LOADER = Path(__file__).resolve().parent.parent / "desktop/Sources/ARCHiDesktop/CompanionVisualTreatment.swift"


def checked_path(path, *, missing=False):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("Use an absolute path without parent traversal")
    for part in reversed([path, *path.parents]):
        try:
            mode = part.lstat().st_mode
        except FileNotFoundError:
            if missing:
                return None
            raise ValueError(f"Required path is missing: {path.name}") from None
        if stat.S_ISLNK(mode):
            raise ValueError(f"Symlink rejected: {part.name}")
        if part != path and not stat.S_ISDIR(mode):
            raise ValueError("A path ancestor is not a directory")
    return path


def read_regular(path, limit, *, missing=False):
    path = checked_path(path, missing=missing)
    if path is None:
        return None
    # O_NONBLOCK avoids waiting if a concurrently replaced path becomes a FIFO.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size < limit:
            raise ValueError(f"Not a bounded regular file: {path.name}")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(limit)
        if len(data) != info.st_size or len(data) >= limit:
            raise ValueError(f"File changed or exceeded the bound: {path.name}")
        return data
    finally:
        os.close(fd)


def verify_loader(loader):
    text = read_regular(loader, 512 * 1024).decode("utf-8")
    for filename, (key, digest) in APPROVED.items():
        for field, expected in [(key + "Filename", filename[:-4]), (key + "Digest", digest)]:
            values = re.findall(r"\bstatic\s+let\s+" + field + r'\s*=\s*"([^"\r\n]+)"', text)
            if values != [expected]:
                raise ValueError(f"Native loader pin differs or is ambiguous: {field}")


def portrait(path, digest, *, missing=False):
    data = read_regular(path, MAXIMUM_BYTES, missing=missing)
    if data is None:
        return None
    if hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f"Companion portrait hash mismatch: {path.name}")
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR" or struct.unpack(">II", data[16:24]) != (512, 512):
        raise ValueError(f"Companion portrait is not the expected 512px PNG: {path.name}")
    return data


def package(destination, *, source=None, installed=DEFAULT_INSTALLED, loader=DEFAULT_LOADER):
    verify_loader(loader)
    destination = checked_path(destination)
    if not destination.is_dir():
        raise ValueError("CompanionArt destination must be a generated directory")
    installed = Path(installed)
    for input_root in [Path(source)] if source is not None else [installed]:
        if destination == input_root or input_root in destination.parents or destination in input_root.parents:
            raise ValueError("Generated destination must be separate from source artwork")
    existing_by_name = {name: portrait(destination / name, digest, missing=True)
                        for name, (_, digest) in APPROVED.items()}
    if source is not None:
        source = checked_path(source)
        if not source.is_dir():
            raise ValueError("Explicit companion source must be a directory")
    else:
        installed = checked_path(installed, missing=True) if any(value is None for value in existing_by_name.values()) else None
        if installed is not None and not installed.is_dir():
            raise ValueError("Installed companion source must be a directory")

    plan, result = {}, {"retained": [], "copied": [], "unavailable": []}
    for filename, (_, digest) in APPROVED.items():
        existing = existing_by_name[filename]
        # An explicitly requested source is validated in full even when the
        # generated bundle already contains its correctly pinned destination.
        supplied = portrait(source / filename, digest) if source is not None else None
        if existing is not None:
            result["retained"].append(filename)
            continue
        if source is None and installed is not None:
            supplied = portrait(installed / filename, digest, missing=True)
        if supplied is None:
            result["unavailable"].append(filename)
        else:
            plan[filename] = supplied

    # Validate every input before writing anything. Exclusive creation protects
    # a concurrently created destination; failure prevents later installation.
    for filename, data in plan.items():
        target = destination / filename
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        portrait(target, APPROVED[filename][1])
        result["copied"].append(filename)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--installed-source", type=Path, default=DEFAULT_INSTALLED)
    parser.add_argument("--loader", type=Path, default=DEFAULT_LOADER)
    args = parser.parse_args()
    try:
        result = package(args.destination, source=args.source, installed=args.installed_source, loader=args.loader)
    except (ValueError, OSError, UnicodeError) as error:
        print(f"Companion artwork qualification failed: {error}. Nothing was installed.", file=sys.stderr)
        return 1
    for state in ("retained", "copied", "unavailable"):
        if result[state]:
            print(f"Companion supplement {state}: {', '.join(result[state])}")
    if result["unavailable"]:
        print("Missing optional portraits remain unsupported; no substitute artwork was installed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
