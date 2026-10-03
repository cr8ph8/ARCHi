#!/usr/bin/env python3
"""Package the frozen local record reader, without importing it into chat."""
import hashlib
from pathlib import Path
import shutil
import sys

EXPECTED = "b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0"


def package(source, destination):
    reader = source / "reader.qualified.json"
    if reader.is_symlink() or not reader.is_file() or reader.stat().st_size > 1024 * 1024:
        raise ValueError("Missing bounded record reader")
    if hashlib.sha256(reader.read_bytes()).hexdigest() != EXPECTED:
        raise ValueError("Frozen record reader changed")
    destination.mkdir(parents=True, exist_ok=False)
    copied = destination / reader.name
    shutil.copy2(reader, copied)
    if hashlib.sha256(copied.read_bytes()).hexdigest() != EXPECTED:
        raise ValueError("Copied record reader differs")
    print("Packaged frozen task-scoped record reader")


if __name__ == "__main__":
    package(*map(Path, sys.argv[1:]))
