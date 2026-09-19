#!/usr/bin/env python3
"""Archive only a candidate's verified source allowlist, never its working data.

Creates NEW archive/receipt paths. Deterministic gzip/tar metadata, a complete
read-back and a final source recheck bind the archive to the checksum manifest.
This is packaging evidence, not asset permission or publication authorization.
"""
from __future__ import annotations

import argparse
import gzip
import io
import json
from pathlib import Path
import re
import tarfile
import sys

import source_release_preflight as preflight


def snapshot(root: Path):
    paths, blockers = preflight.collect(root)
    if blockers:
        raise ValueError("Candidate source scope has unresolved blockers")
    inventory, contents = [], {}
    for relative in paths:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or path.as_posix() != relative or "\n" in relative:
            raise ValueError("Unsafe archive member path")
        if preflight.linked(root, relative):
            raise ValueError("Source link is not an archive input")
        data = (root / path).read_bytes()
        if preflight.scan(relative, data):
            raise ValueError("Candidate has unreviewed metadata or private-value findings")
        inventory.append({"path": relative, "sha256": preflight.sha(data), "bytes": len(data),
                          "executable": bool((root / path).stat().st_mode & 0o111)})
        contents[relative] = data
    manifest = "".join(f"{row['sha256']}  {row['path']}\n" for row in inventory).encode()
    if preflight.linked(root, "SOURCE_SHA256SUMS") or (root / "SOURCE_SHA256SUMS").read_bytes() != manifest:
        raise ValueError("Candidate checksum manifest is missing or stale")
    contents["SOURCE_SHA256SUMS"] = manifest
    return inventory, contents


def archive(root: Path, archive_path: Path, receipt_path: Path):
    if root.is_symlink() or not root.is_dir():
        raise ValueError("Expected a regular candidate directory")
    root = root.resolve()
    outputs = [archive_path.absolute(), receipt_path.absolute()]
    if outputs[0] == outputs[1]:
        raise ValueError("Archive and receipt require different paths")
    for path in outputs:
        if path.exists() or path.is_symlink() or not path.parent.is_dir() or root in path.resolve().parents:
            raise ValueError("Use new outputs outside the frozen candidate")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,100}", root.name):
        raise ValueError("Candidate directory needs a portable archive prefix")
    inventory, contents = snapshot(root)
    executable = {row["path"]: row["executable"] for row in inventory}
    expected = {root.name + "/" + relative: data for relative, data in contents.items()}
    # An empty gzip filename and zero timestamp avoid machine/path/time metadata.
    with archive_path.open("xb") as destination:
        with gzip.GzipFile(fileobj=destination, mode="wb", filename="", mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as tar:
                for relative, data in sorted(contents.items()):
                    info = tarfile.TarInfo(root.name + "/" + relative)
                    info.size = len(data)
                    info.mode = 0o755 if executable.get(relative, False) else 0o644
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    tar.addfile(info, io.BytesIO(data))
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        if len(members) != len(expected) or {m.name for m in members} != set(expected):
            raise ValueError("Archive read-back member set differs")
        for member in members:
            if not member.isfile() or member.uid or member.gid or member.mtime or member.uname or member.gname:
                raise ValueError("Unexpected archive metadata or member type")
            relative = member.name.removeprefix(root.name + "/")
            if member.mode != (0o755 if executable.get(relative, False) else 0o644):
                raise ValueError("Archive mode differs")
            with tar.extractfile(member) as stream:
                if stream.read() != expected[member.name]:
                    raise ValueError("Archive bytes differ from the source snapshot")
    after, after_contents = snapshot(root)
    if after != inventory or after_contents != contents:
        raise ValueError("Candidate changed during archive creation")
    result = {"schema": "archi-source-archive/v1", "status": "ARCHIVE_VERIFIED", "candidate": str(root),
              "archive": str(archive_path.absolute()), "archiveSha256": preflight.sha(archive_path.read_bytes()),
              "archiveBytes": archive_path.stat().st_size, "members": len(expected),
              "sourceFileCount": len(inventory), "sourceInventoryDigest": preflight.sha(preflight.json_bytes(inventory)),
              "checksumManifestSha256": preflight.sha(contents["SOURCE_SHA256SUMS"]),
              "readBackAllMembersMatched": True, "sourceUnchanged": True,
              "metadata": "Sorted regular-file members, normalized modes, UID/GID/time zero, no owner names or gzip filename.",
              "publicationAuthorized": False, "notarizedAppReady": False}
    preflight.write_new(receipt_path, preflight.json_bytes(result))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = archive(args.candidate, args.archive, args.receipt)
        print(json.dumps({key: result[key] for key in ("status", "archiveSha256", "members", "sourceInventoryDigest")}, indent=2))
        return 0
    except (OSError, ValueError, tarfile.TarError):
        print("Archive preparation stopped. Check source integrity and new output paths; existing output is preserved.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
