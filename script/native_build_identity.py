#!/usr/bin/env python3
"""Bind native source inputs and an unsigned packaged payload to a candidate.

This is build provenance, not a signature or a hermetic-build attestation.
The outer signer may subsequently change executable bytes. Final signed-bundle
hashes belong in an external delivery receipt, not in a self-hashing bundle.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import uuid


SOURCE_SCHEMA = "archi-native-source-inputs/v1"
BUILD_SCHEMA = "archi-native-build-identity/v1"
RECEIPT = "Contents/Resources/ARCHiBuildIdentity.json"
REQUIRED = (
    "desktop/Package.swift", "desktop/Sources", "desktop/Tests",
    "shared/ARCHiSpatial/Package.swift", "shared/ARCHiSpatial/Sources",
    "shared/ARCHiSpatial/Tests",
)
OPTIONAL = (
    "desktop/Package.resolved", "desktop/.swiftpm/configuration",
    "shared/ARCHiSpatial/Package.resolved", "shared/ARCHiSpatial/.swiftpm/configuration",
)
IGNORED = {".DS_Store", "__pycache__"}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def file_record(path, relative):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f"Not a regular build input: {relative}")
        h = hashlib.sha256()
        with os.fdopen(fd, "rb", closefd=False) as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                h.update(block)
        after = os.fstat(fd)
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise ValueError(f"Build input changed while reading: {relative}")
        return {"path": relative, "kind": "file", "mode": stat.S_IMODE(before.st_mode),
                "bytes": before.st_size, "sha256": h.hexdigest()}
    finally:
        os.close(fd)


def inventory(root, selected, *, allow_internal_links=False, ignored=IGNORED):
    records = []

    def visit(path):
        relative = path.relative_to(root).as_posix()
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            target = os.readlink(path)
            if not allow_internal_links or Path(target).is_absolute() or not path.resolve(strict=True).is_relative_to(root):
                raise ValueError(f"Unsupported or escaping build-input link: {relative}")
            records.append({"path": relative, "kind": "link", "target": target})
        elif stat.S_ISDIR(mode):
            records.append({"path": relative, "kind": "directory", "mode": stat.S_IMODE(mode)})
            for child in sorted(path.iterdir()):
                if child.name not in ignored:
                    visit(child)
        elif stat.S_ISREG(mode):
            records.append(file_record(path, relative))
        else:
            raise ValueError(f"Unsupported build input: {relative}")

    for relative in selected:
        path = root / relative
        # Reject a link in any selected input's ancestors, not just its leaf.
        for ancestor in path.relative_to(root).parents:
            if (root / ancestor).is_symlink():
                raise ValueError(f"Linked input ancestor: {relative}")
        visit(path)
    return sorted(records, key=lambda row: row["path"])


def source_inputs(repo):
    repo = repo.resolve(strict=True)
    if not repo.is_dir():
        raise ValueError("Source root must be a directory")
    selected = list(REQUIRED)
    for relative in REQUIRED:
        path = repo / relative
        if not path.exists():
            raise ValueError(f"Missing required native input: {relative}")
        if path.is_dir() != (not relative.endswith(".swift")):
            raise ValueError(f"Wrong native input type: {relative}")
    absent = []
    for relative in OPTIONAL:
        if (repo / relative).exists() or (repo / relative).is_symlink():
            selected.append(relative)
        else:
            absent.append(relative)
    scripts = repo / "script"
    if not scripts.is_dir() or scripts.is_symlink():
        raise ValueError("Missing or linked packaging recipe directory")
    selected.extend(p.relative_to(repo).as_posix() for p in sorted(scripts.iterdir())
                    if p.suffix in {".py", ".sh"})
    for name in ("build_and_run.sh", "native_build_identity.py"):
        if not (scripts / name).is_file():
            raise ValueError(f"Missing packaging recipe: {name}")
    records = inventory(repo, selected)
    # Fail closed when the package graph changes. Extend this scope deliberately
    # before introducing a remote or additional local dependency. The inventory
    # above rejects linked/special input paths before reading these manifests.
    manifest = (repo / "desktop/Package.swift").read_text()
    declarations = re.findall(r"\.package\s*\(([^)]*)\)", manifest)
    if len(declarations) != 1 or not re.fullmatch(r'\s*path\s*:\s*"../shared/ARCHiSpatial"\s*', declarations[0]):
        raise ValueError("Native dependency graph changed; review build identity input scope")
    shared = (repo / "shared/ARCHiSpatial/Package.swift").read_text()
    if re.search(r"\.package\s*\(", shared):
        raise ValueError("Shared dependency graph changed; review build identity input scope")
    value = {"files": records, "absentOptionalInputs": absent}
    return {"schema": SOURCE_SCHEMA, "sourceContentID": digest(value), **value}


def bundle_version(now):
    # A UTC minute counter encoded within Apple's 4/2/2 digit limits. The UUID,
    # not this clock value, distinguishes candidates created in the same minute.
    minute = int((now - datetime(2020, 1, 1, tzinfo=timezone.utc)).total_seconds() // 60)
    if not 0 <= minute < 99_990_000:
        raise ValueError("Build clock is outside the supported bundle-version range")
    return f"{minute // 10000 + 1}.{minute // 100 % 100}.{minute % 100}"


def capture(repo, output, *, verification_requested, compiler):
    value = source_inputs(repo)
    value["buildOptions"] = {"configuration": "debug", "verificationRequested": verification_requested}
    # The version descriptor is useful context, not a hash of the SDK/compiler.
    value["compilerVersion"] = compiler.strip()
    if not value["compilerVersion"]:
        raise ValueError("Swift compiler version is unavailable")
    with output.open("x") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def seal(repo, snapshot, bundle, *, now=None):
    before = json.loads(snapshot.read_text())
    current = source_inputs(repo)
    if any(before.get(key) != current[key] for key in current):
        raise ValueError("Native source/build inputs changed during the build; nothing was promoted")
    bundle = bundle.resolve(strict=True)
    if not bundle.is_dir() or bundle.suffix != ".app":
        raise ValueError("Expected a generated .app bundle")
    destination = bundle / RECEIPT
    if destination.exists() or destination.is_symlink():
        raise ValueError("Candidate already has a build identity")
    for relative in ("Contents/MacOS/ARCHiDesktop", "Contents/Resources"):
        path = bundle / relative
        if not path.exists():
            raise ValueError(f"Missing packaged input: {relative}")
        if path.is_symlink() or path.is_dir() != relative.endswith("Resources"):
            raise ValueError(f"Wrong or linked packaged input: {relative}")
    # Inspect links before reading the plist, including links in its ancestors.
    payload = inventory(bundle, ["Contents"], allow_internal_links=True, ignored=())
    info_path = bundle / "Contents/Info.plist"
    if info_path.is_symlink():
        raise ValueError("Linked bundle property list")
    info = plistlib.loads(info_path.read_bytes())
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != "com.quotient.archi.desktop.review":
        raise ValueError("Unexpected native bundle identity")
    now = now or datetime.now(timezone.utc)
    candidate = str(uuid.uuid4())
    inputs = {"sourceContentID": current["sourceContentID"], "preSignPayloadID": digest(payload),
              "buildOptions": before["buildOptions"], "compilerVersion": before["compilerVersion"]}
    receipt = {"schema": BUILD_SCHEMA, "candidateID": candidate, "contentID": digest(inputs),
               "createdAtUTC": now.isoformat(), "bundleVersion": bundle_version(now), **inputs,
               "sourceInputs": current,
               "preSignPayload": payload,
               "scope": "Source inputs matched before Swift compilation and before outer signing. Packaged payload hashes describe bytes before identity stamping and outer signing, not final signed artifact hashes.",
               "exclusions": ["This receipt and identity plist fields added after payload capture", "outer code signature added later", "xattrs, ACLs and filesystem timestamps", "compiler and SDK bytes; compiler version is descriptive only"],
               "limits": "A matching before/after input inventory is not an immutable source snapshot, clean-Git claim, hermetic build, runtime qualification or release approval."}
    info.update(CFBundleVersion=receipt["bundleVersion"], ARCHiCandidateID=candidate,
                ARCHiSourceContentID=current["sourceContentID"], ARCHiBuildContentID=receipt["contentID"])
    with destination.open("x") as stream:
        json.dump(receipt, stream, indent=2)
        stream.write("\n")
    info_path.write_bytes(plistlib.dumps(info))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    first = sub.add_parser("capture")
    first.add_argument("repo", type=Path)
    first.add_argument("output", type=Path)
    first.add_argument("--verify", choices=("0", "1"), required=True)
    last = sub.add_parser("seal")
    last.add_argument("repo", type=Path)
    last.add_argument("snapshot", type=Path)
    last.add_argument("bundle", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "capture":
            compiler = subprocess.check_output(["swift", "--version"], text=True)
            capture(args.repo, args.output, verification_requested=args.verify == "1", compiler=compiler)
        else:
            result = seal(args.repo, args.snapshot, args.bundle)
            print(f"Candidate {result['candidateID']} · build {result['bundleVersion']} · content {result['contentID']}")
    except (OSError, ValueError, RuntimeError, KeyError, plistlib.InvalidFileException, subprocess.SubprocessError) as error:
        print(f"Build identity refused: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
