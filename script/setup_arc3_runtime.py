#!/usr/bin/env python3
"""Create a native offline ARC3 runtime without modifying an existing checkout.

Run explicitly with a native Python 3.12+. Downloads pinned SDK wheels from
PyPI. It copies only the caller's named existing game folder and runs no games.
"""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys
import venv


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-environments", type=Path, required=True)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if sys.version_info < (3, 12) or sys.platform != "darwin":
        parser.error("Use native macOS Python 3.12 or later.")
    arch = platform.machine()
    if arch not in {"arm64", "x86_64"}:
        parser.error("Unsupported architecture.")
    source = args.source_environments.expanduser().resolve(strict=True)
    if not source.is_dir() or not list(source.glob("*/*/metadata.json")):
        parser.error("Choose an existing ARC3 environment_files folder with game metadata.")
    files = sorted(p for p in source.rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    if any(p.is_symlink() for p in source.rglob("*")):
        parser.error("Environment symlinks are not copied. Review a regular game folder first.")
    destination = args.destination or (Path.home() / "Library/Application Support/ARCHi" / f"ARC3Runtime-{arch}-v1")
    destination = destination.expanduser().absolute()
    if destination.exists() or destination.is_symlink():
        parser.error("Destination already exists. Nothing will be overwritten; choose a new destination.")
    inventory = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    destination.mkdir(parents=True, exist_ok=False)
    # Keep partial failures for diagnosis; only the final receipt admits this
    # directory to native default discovery. No existing runtime is modified.
    venv.EnvBuilder(with_pip=True, symlinks=False).create(destination / ".venv")
    interpreter = destination / ".venv/bin/python"
    subprocess.run([str(interpreter), "-I", "-m", "pip", "--isolated", "install",
                    "--index-url", "https://pypi.org/simple", "--only-binary=:all:",
                    "--disable-pip-version-check", "arc-agi==0.9.8", "arcengine==0.9.3"], check=True)
    subprocess.run([str(interpreter), "-I", "-c",
                    "import platform,importlib.metadata as m; from arc_agi import Arcade; from arcengine import GameAction; "
                    "assert platform.machine()==" + repr(arch) + "; "
                    "assert m.version('arc-agi')=='0.9.8'; assert m.version('arcengine')=='0.9.3'"], check=True,
                   cwd=destination, env={"PATH": os.defpath, "HOME": str(destination), "PYTHON_DOTENV_DISABLED": "1"})
    for name, expected in inventory.items():
        target = destination / "environment_files" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / name, target)
        if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            raise RuntimeError("Environment changed during copy; runtime not admitted.")
    packages = json.loads(subprocess.check_output([str(interpreter), "-I", "-m", "pip", "--isolated", "list", "--format=json"], text=True))
    receipt = {"schema": "archi-arc3-runtime/v1", "architecture": arch,
               "python": sys.version.split()[0], "baseInterpreter": str(Path(sys.executable).resolve()),
               "packages": packages, "environmentFiles": inventory, "gameExecution": False}
    (destination / "runtime-ready.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"ARC3 runtime ready: {destination}")


if __name__ == "__main__":
    main()
