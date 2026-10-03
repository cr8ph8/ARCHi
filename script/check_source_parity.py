#!/usr/bin/env python3
"""Read-only, byte-exact comparison of authored and publication code.

The fixed product scopes are a filesystem union, including untracked additions.
Ancillary code is selected only from the publication Git index. Assets, profiles,
build outputs and other unselected files are never opened. A reviewed exception
admits one exact pair of unequal SHA-256 hashes, never a normalization or glob.
This command has no copy, synchronization, report-file, or other write option.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys


TOP_LEVEL = {
    "desktop/Sources/ARCHiDesktop": {".swift"},
    "desktop/Tests/ARCHiDesktopTests": {".swift"},
    "shared/ARCHiSpatial/Sources/ARCHiSpatial": {".swift"},
    "shared/ARCHiSpatial/Tests/ARCHiSpatialTests": {".swift"},
    "src": {".ts", ".css"},
}
UNITY = "unity/ARCHi/Assets/ARCHi"
TRACKED_ROOTS = ("script", "scripts", "unity/ARCHi/Packages")
CODE_SUFFIXES = {
    ".sh", ".bash", ".zsh", ".py", ".mjs", ".cjs", ".js", ".ts", ".tsx",
    ".css", ".swift", ".cs", ".c", ".h", ".cpp", ".hpp", ".mm", ".metal",
    ".shader", ".hlsl", ".cginc", ".compute", ".uss", ".uxml",
}
IGNORED_DIRECTORIES = {
    ".git", ".codex", ".build", ".swiftpm", "__pycache__", "node_modules",
    "Library", "Temp", "Logs", "UserSettings", "Builds", "build", "dist",
    "output", "outputs", "ArtSources", "profiles", "Profiles", "private-archive",
}
HASH = re.compile(r"[0-9a-f]{64}\Z")


class InputError(Exception):
    def __init__(self, code: str, input_name: str):
        self.code = code
        self.input_name = input_name


def relative_path(value: object) -> bool:
    return (isinstance(value, str) and bool(value) and "\\" not in value
            and not any(ord(c) < 32 or ord(c) == 127 for c in value)
            and not PurePosixPath(value).is_absolute()
            and all(part not in {".", ".."} for part in value.split("/"))
            and PurePosixPath(value).as_posix() == value)


def checked_input_path(value: str, name: str, directory: bool) -> Path:
    # Check the original ancestry before normalizing '..', so a symlink followed
    # by '..' cannot disappear during lexical normalization.
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    current = Path(path.anchor)
    try:
        for part in path.parts[1:]:
            current = current / part
            info = current.lstat()
            if stat.S_ISLNK(info.st_mode):
                raise InputError("SYMLINK_INPUT", name)
        info = current.lstat()
        valid = stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)
        if not valid:
            raise InputError("INVALID_INPUT_TYPE", name)
    except OSError:
        raise InputError("INPUT_UNAVAILABLE", name) from None
    return Path(os.path.abspath(path))


def inspect(root: Path, relative: str) -> tuple[str, str]:
    """Check every ancestor without following links; return first failed path."""
    current = root
    parts = PurePosixPath(relative).parts
    for index, part in enumerate(parts):
        current = current / part
        prefix = "/".join(parts[:index + 1])
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            return "MISSING", relative
        except OSError:
            return "UNREADABLE", prefix
        if stat.S_ISLNK(mode):
            return "SYMLINK", prefix
        if index < len(parts) - 1 and not stat.S_ISDIR(mode):
            return "NOT_DIRECTORY", prefix
    if stat.S_ISREG(mode):
        return "FILE", relative
    if stat.S_ISDIR(mode):
        return "DIRECTORY", relative
    return "NOT_REGULAR", relative


def problem(code: str, path: str, side: str) -> dict:
    return {"code": code, "path": path, "side": side}


def ignored(relative: str) -> bool:
    return bool(set(PurePosixPath(relative).parts[:-1]) & IGNORED_DIRECTORIES)


def inventory(root: Path, side: str) -> tuple[set[str], list[dict]]:
    paths, differences = set(), []

    def visit(relative: str, suffixes: set[str], recursive: bool) -> None:
        kind, failed = inspect(root, relative)
        if kind == "MISSING":
            return
        if kind != "DIRECTORY":
            differences.append(problem("NOT_DIRECTORY" if kind == "FILE" else kind, failed, side))
            return
        try:
            with os.scandir(root / relative) as entries:
                children = sorted(entries, key=lambda entry: entry.name)
        except OSError:
            differences.append(problem("UNREADABLE", relative, side))
            return
        for entry in children:
            child = relative + "/" + entry.name
            if not relative_path(child):
                raise InputError("INVALID_SCOPED_PATH", side)
            if entry.name in IGNORED_DIRECTORIES:
                continue
            # Recursive directory links are rejected without looking at targets.
            # Top-level scopes never inspect their unselected nested directories.
            if recursive and entry.is_symlink():
                differences.append(problem("SYMLINK", child, side))
            elif recursive and entry.is_dir(follow_symlinks=False):
                visit(child, suffixes, True)
            elif PurePosixPath(entry.name).suffix in suffixes:
                paths.add(child)

    for relative, suffixes in TOP_LEVEL.items():
        visit(relative, suffixes, False)
    for relative in ("desktop/Package.swift", "shared/ARCHiSpatial/Package.swift"):
        kind, failed = inspect(root, relative)
        if kind == "FILE":
            paths.add(relative)
        elif kind != "MISSING":
            differences.append(problem("NOT_REGULAR" if kind == "DIRECTORY" else kind, failed, side))
    visit(UNITY, {".cs", ".shader"}, True)
    # These are only ancestry checks. Never scan untracked ancillary content.
    for relative in TRACKED_ROOTS:
        kind, failed = inspect(root, relative)
        if kind not in {"MISSING", "DIRECTORY"}:
            differences.append(problem("NOT_DIRECTORY" if kind == "FILE" else kind, failed, side))
    return paths, differences


def tracked_code(publication: Path) -> tuple[set[str], set[str]]:
    env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
    env.update(GIT_OPTIONAL_LOCKS="0", GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
    command = ["git", "-c", "core.fsmonitor=false", "-C", str(publication)]
    try:
        prefix = subprocess.run(command + ["rev-parse", "--show-prefix"], env=env,
                                capture_output=True, check=True, timeout=30)
        if prefix.stdout.strip():
            raise InputError("PUBLICATION_NOT_REPOSITORY_ROOT", "publication")
        result = subprocess.run(command + ["ls-files", "--stage", "-z", "--", *TRACKED_ROOTS],
                                env=env, capture_output=True, check=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        raise InputError("PUBLICATION_GIT_UNAVAILABLE", "publication") from None
    paths, links = set(), set()
    for record in result.stdout.split(b"\0"):
        if not record:
            continue
        try:
            metadata, encoded_path = record.split(b"\t", 1)
            mode, _, stage = metadata.split()
            relative = encoded_path.decode("utf-8")
        except (ValueError, UnicodeError):
            raise InputError("INVALID_GIT_INVENTORY", "publication") from None
        if not relative_path(relative):
            raise InputError("INVALID_GIT_PATH", "publication")
        if not any(relative.startswith(scope + "/") for scope in TRACKED_ROOTS):
            continue
        if ignored(relative) or PurePosixPath(relative).suffix not in CODE_SUFFIXES:
            continue
        if stage != b"0":
            raise InputError("UNMERGED_PUBLICATION_CODE", "publication")
        paths.add(relative)
        if mode == b"120000":
            links.add(relative)
    return paths, links


def unique_object(pairs: list[tuple]) -> dict:
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate key")
        value[key] = item
    return value


def read_policy(path: str | None) -> dict[str, dict]:
    if path is None:
        return {}
    file = checked_input_path(path, "policy", False)
    try:
        with file.open("rb") as stream:
            raw = stream.read(1_048_577)
        if len(raw) > 1_048_576:
            raise ValueError("oversized")
        value = json.loads(raw, object_pairs_hook=unique_object)
        if (not isinstance(value, dict) or set(value) != {"schemaVersion", "reviewedDifferences"}
                or type(value["schemaVersion"]) is not int or value["schemaVersion"] != 1
                or not isinstance(value["reviewedDifferences"], list)):
            raise ValueError("schema")
        result = {}
        for entry in value["reviewedDifferences"]:
            if (not isinstance(entry, dict)
                    or set(entry) != {"path", "sourceSHA256", "publicationSHA256", "reason"}
                    or not relative_path(entry["path"])
                    or not isinstance(entry["reason"], str) or not entry["reason"].strip()
                    or any(not isinstance(entry[key], str) or not HASH.fullmatch(entry[key])
                           for key in ("sourceSHA256", "publicationSHA256"))):
                raise ValueError("entry")
            if entry["path"] in result:
                raise ValueError("duplicate path")
            result[entry["path"]] = entry
        return result
    except (OSError, ValueError, UnicodeError):
        raise InputError("INVALID_POLICY", "policy") from None


def digest(root: Path, relative: str) -> str:
    # Descriptor-relative opens protect both files and ancestors from link swaps.
    descriptors = []
    try:
        parent = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        descriptors.append(parent)
        parts = PurePosixPath(relative).parts
        for part in parts[:-1]:
            parent = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            descriptors.append(parent)
        descriptor = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
        descriptors.append(descriptor)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("not regular")
        result = hashlib.sha256()
        while True:
            chunk = os.read(descriptor, 1_048_576)
            if not chunk:
                return result.hexdigest()
            result.update(chunk)
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


def compare(source: Path, publication: Path, policy: dict[str, dict]) -> dict:
    source_paths, differences = inventory(source, "source")
    publication_paths, publication_issues = inventory(publication, "publication")
    differences.extend(publication_issues)
    tracked, indexed_links = tracked_code(publication)
    paths = source_paths | publication_paths | tracked
    matched, compared, reviewed = 0, 0, []
    used_policy = set()
    for relative in sorted(paths):
        hashes = {}
        for side, root in (("source", source), ("publication", publication)):
            kind, failed = inspect(root, relative)
            if side == "publication" and relative in indexed_links:
                differences.append(problem("SYMLINK", relative, side))
            elif kind != "FILE":
                differences.append(problem("NOT_REGULAR" if kind == "DIRECTORY" else kind, failed, side))
            else:
                try:
                    hashes[side + "SHA256"] = digest(root, relative)
                except OSError:
                    differences.append(problem("UNREADABLE_OR_CHANGED_DURING_CHECK", relative, side))
        if len(hashes) != 2:
            continue
        compared += 1
        if hashes["sourceSHA256"] == hashes["publicationSHA256"]:
            matched += 1
        elif relative in policy and all(policy[relative][key] == value for key, value in hashes.items()):
            reviewed.append({"path": relative, **hashes, "reason": policy[relative]["reason"]})
            used_policy.add(relative)
        else:
            differences.append({"code": "CHANGED", "path": relative, **hashes})
    for relative in sorted(policy.keys() - used_policy):
        differences.append({"code": "UNUSED_OR_STALE_POLICY", "path": relative})
    differences = sorted({json.dumps(item, sort_keys=True): item for item in differences}.values(),
                         key=lambda item: (item["path"], item["code"], item.get("side", "")))
    return {"schemaVersion": 1, "status": "different" if differences else "match",
            "counts": {"selected": len(paths), "compared": compared, "matched": matched,
                       "reviewed": len(reviewed), "differences": len(differences),
                       "policyEntries": len(policy)},
            "differences": differences, "reviewedDifferences": reviewed}


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise InputError("INVALID_ARGUMENTS", "arguments")


def main(argv: list[str] | None = None) -> int:
    parser = Parser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--publication", required=True)
    parser.add_argument("--policy")
    try:
        args = parser.parse_args(argv)
        source = checked_input_path(args.source, "source", True)
        publication = checked_input_path(args.publication, "publication", True)
        result = compare(source, publication, read_policy(args.policy))
        status = 0 if result["status"] == "match" else 1
    except InputError as error:
        result = {"schemaVersion": 1, "status": "inputError",
                  "errors": [{"code": error.code, "input": error.input_name}]}
        status = 2
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return status


if __name__ == "__main__":
    sys.exit(main())
