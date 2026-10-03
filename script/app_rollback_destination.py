#!/usr/bin/env python3
"""Reserve a private, same-filesystem rollback destination for an ARCHi app."""

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import plistlib
import stat
import sys
import tempfile


def _checked_path(path: Path) -> Path:
    """Reject symlinks before any path is used for bundle or recovery access."""
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError(f"Expected an absolute path without '..': {path}")
    for component in (*reversed(path.parents), path):
        try:
            mode = component.lstat().st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode):
            raise ValueError(f"Refusing a symlink in the rollback path: {component}")
    return path


def _require_writable_directory(path: Path) -> None:
    info = _checked_path(path).stat()
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError(f"Expected a directory: {path}")
    if not info.st_mode & 0o222 or not os.access(path, os.W_OK | os.X_OK):
        raise ValueError(f"Rollback directory is not writable: {path}")


def _private_directory(path: Path) -> None:
    _checked_path(path)
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    _require_writable_directory(path)
    info = path.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError(f"Recovery directory must be owned by this user with mode 0700: {path}")


def _device_id(path: Path) -> int:
    return path.stat().st_dev


def reserve_rollback_destination(app_dir: Path, app_identifier: str, home: Path) -> Path:
    """Validate the current bundle, then reserve an empty path without moving it."""
    _checked_path(app_dir)
    if not app_dir.is_dir() or app_dir.suffix.lower() != ".app":
        raise ValueError(f"Expected the existing installed app bundle: {app_dir}")
    info_path = _checked_path(app_dir / "Contents" / "Info.plist")
    with info_path.open("rb") as stream:
        info = plistlib.load(stream)
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != app_identifier or info.get("CFBundlePackageType") != "APPL":
        raise ValueError(f"Installed bundle does not have the expected app identity: {app_dir}")
    _require_writable_directory(app_dir.parent)

    support = _checked_path(home / "Library" / "Application Support")
    if any(part.lower() == "applications" or part.lower().endswith(".app") for part in support.parts):
        raise ValueError(f"Recovery must stay outside Applications and app bundles: {support}")
    # These ordinary parent directories may already have user-selected modes.
    # Only our recovery directories are required to be private.
    for parent in (home, home / "Library", support):
        _checked_path(parent)
        if parent == home:
            _require_writable_directory(parent)
        else:
            try:
                parent.mkdir(mode=0o700)
            except FileExistsError:
                pass
            _require_writable_directory(parent)
    recovery = support / "ARCHiRecovery"
    rollbacks = recovery / "Rollbacks"
    _private_directory(recovery)
    _private_directory(rollbacks)
    if len({_device_id(app_dir), _device_id(app_dir.parent), _device_id(rollbacks)}) != 1:
        raise ValueError("Installed app and recovery must be on the same filesystem; no bundle was moved.")

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    reservation = Path(tempfile.mkdtemp(prefix=f"{stamp}-", dir=rollbacks))
    _private_directory(reservation)
    return reservation / app_dir.name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app_dir", type=Path)
    parser.add_argument("app_identifier")
    args = parser.parse_args()
    try:
        destination = reserve_rollback_destination(args.app_dir, args.app_identifier, Path.home())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"Could not reserve an ARCHi rollback: {error}", file=sys.stderr)
        return 1
    print(destination)
    return 0


if __name__ == "__main__":
    sys.exit(main())
