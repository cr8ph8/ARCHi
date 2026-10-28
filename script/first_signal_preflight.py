#!/usr/bin/env python3
"""Preserve First Signal bytes before a native app can be promoted.

No app launch, profile/save access, bookmark changes, install or migration.
An inventory is preservation evidence, not gameplay/save compatibility proof.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import sys


OWNER = {
    "appIdentifier": "com.quotient.archi.desktop.review",
    "origin": "http://127.0.0.1:8767/",
    "dataStoreID": "A4A19A25-351B-45B6-9D70-3B15D0A02817",
    "saveKey": "qimon.first-signal.chapter.v1",
    "defaultsSuite": "com.quotient.archi.qimon-local-play",
    "selectionKey": "selectedEmbeddedFolder.v1",
}
CHAPTER = "Contents/Resources/QiMonFirstSignalWeb"
RECEIPT = "Contents/Resources/FirstSignalPreservation.json"
HOST = "desktop/Sources/ARCHiDesktop/QiMonEmbeddedGame.swift"
MANIFEST_SCHEMA = "archi-first-signal-resources/v1"
PLAN_SCHEMA = "archi-first-signal-preservation/v1"


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def write_new(path, value):
    # Do not follow an output link or replace an earlier evidence file.
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def checked(path):
    path = Path(os.path.abspath(path))
    # /var and /tmp are system aliases on macOS. Resolve the parent once, but
    # reject a linked leaf; chapter traversal below rejects every nested link.
    if path.is_symlink():
        raise ValueError(f"Linked input is not preservation evidence: {path}")
    return path.parent.resolve(strict=True) / path.name


def file_record(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f"Not a regular resource: {path}")
        h = hashlib.sha256()
        with os.fdopen(fd, "rb", closefd=False) as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                h.update(block)
        after = os.fstat(fd)
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise ValueError(f"Resource changed while reading: {path}")
        return {"bytes": after.st_size, "sha256": h.hexdigest()}
    finally:
        os.close(fd)


def resources(root):
    root = checked(root)
    if not root.is_dir():
        raise ValueError(f"Missing First Signal chapter: {root}")
    files = {}
    directories = []

    def visit(directory):
        for path in sorted(directory.iterdir()):
            if path.name == ".DS_Store" and path.is_file() and not path.is_symlink():
                continue
            relative = path.relative_to(root).as_posix()
            mode = path.lstat().st_mode
            if path.name.startswith(".") or stat.S_ISLNK(mode):
                raise ValueError(f"Hidden or linked chapter input needs review: {relative}")
            if stat.S_ISDIR(mode):
                directories.append(relative)
                visit(path)
            elif stat.S_ISREG(mode):
                record = file_record(path)
                if record["bytes"] > 64 * 1024 * 1024:
                    raise ValueError(f"Resource exceeds the embedded host limit: {relative}")
                files[relative] = record
            else:
                raise ValueError(f"Special chapter input needs review: {relative}")

    visit(root)
    marker = files.get("qimon-build.json", {})
    index = files.get("index.html", {})
    if not 0 < marker.get("bytes", 0) <= 4096 or not 0 < index.get("bytes", 0) < 131072:
        raise ValueError("Missing or oversized First Signal marker/entry")
    value = load(root / "qimon-build.json")
    if (not isinstance(value, dict) or type(value.get("schema")) is not int or value["schema"] != 1
            or value.get("game") != "qimon-first-signal" or value.get("entry") != "index.html"):
        raise ValueError("Wrong First Signal build marker")
    inventory = {"files": files, "directories": sorted(directories)}
    return {"schema": MANIFEST_SCHEMA, "contentID": digest(inventory), **inventory}


def host_identity(repo):
    source = repo / HOST
    text = source.read_text()
    patterns = {
        "origin": r'static let origin = URL\(string: "([^"]+)"\)',
        "dataStoreID": r'static let dataStoreID = UUID\(uuidString: "([^"]+)"\)',
        "saveKey": r'static let saveKey = "([^"]+)"',
        "selectionKey": r'static let selectionKey = "([^"]+)"',
        "defaultsSuite": r'UserDefaults\(suiteName: "([^"]+)"\)',
    }
    for key, pattern in patterns.items():
        if re.findall(pattern, text) != [OWNER[key]]:
            raise ValueError(f"First Signal save owner changed or cannot be verified: {key}")
    if re.findall(r'static let port: UInt16 = (\d+)', text) != ["8767"]:
        raise ValueError("First Signal origin port changed")
    # The persistent store and origin must still be used, not just declared.
    for literal in ("WKWebsiteDataStore(forIdentifier: Self.dataStoreID)",
                    "port: Self.port", "localStorage.getItem('" + OWNER["saveKey"] + "')"):
        if literal not in text:
            raise ValueError("First Signal storage/host binding needs review")
    return file_record(source)


def selection_evidence(path):
    value = load(path)
    if value.get("schema") != "archi-first-signal-selection/v1" or value.get("owner") != OWNER:
        raise ValueError("Unrecognized First Signal selection owner")
    for key in ("chapter", "earlierAdventure"):
        item = value.get(key)
        if not isinstance(item, dict) or type(item.get("present")) is not bool:
            raise ValueError("Incomplete selection inspection")
        if item["present"]:
            if (item.get("stale") is not False or not isinstance(item.get("path"), str)
                    or not Path(item["path"]).is_absolute()
                    or re.fullmatch(r"[0-9a-f]{64}", str(item.get("sha256"))) is None):
                raise ValueError("Stale or unresolved First Signal selection; keep the working app")
        elif item != {"present": False}:
            raise ValueError("Ambiguous absent selection")
    return value


def installed_identity(app):
    app = checked(app)
    if not app.exists():
        return None
    if not app.is_dir():
        raise ValueError("Installed app is not a directory")
    for relative in ("Contents", "Contents/MacOS", "Contents/Resources"):
        if (app / relative).is_symlink() or not (app / relative).is_dir():
            raise ValueError("Installed app has missing or linked bundle directories")
    info_path = app / "Contents/Info.plist"
    info_record = file_record(info_path)
    info = plistlib.loads(info_path.read_bytes())
    if (info.get("CFBundleIdentifier") != OWNER["appIdentifier"]
            or info.get("CFBundlePackageType") != "APPL" or info.get("CFBundleExecutable") != "ARCHiDesktop"):
        raise ValueError("Installed application identity does not match the saved owner")
    # This separate shortcut has a different save owner. Do not strip a bundled
    # earlier adventure through a web-chapter-only preservation recipe.
    earlier = app / "Contents/Resources/QiMon First Signal.app"
    if earlier.exists() or earlier.is_symlink():
        raise ValueError("Bundled earlier adventure requires its own preservation recipe")
    return {"info": info_record, "executable": file_record(app / "Contents/MacOS/ARCHiDesktop")}


def capture(repo, installed, selection, output, *, build=None, manifest=None):
    repo, installed = repo.resolve(strict=True), checked(installed)
    if (build is None) != (manifest is None):
        raise ValueError("An explicit chapter requires both --build and an independently reviewed --manifest")
    selected = selection_evidence(selection)
    installed_state = installed_identity(installed)
    chapters = {}
    bundled = installed / CHAPTER
    adjacent = installed.parent / "QiMonFirstSignalWeb"
    for path in (bundled, adjacent):
        if path.exists() or path.is_symlink():
            chapters[str(path)] = resources(path)
    explicit = selected["chapter"]
    if explicit["present"]:
        chosen = checked(Path(explicit["path"]))
        # Bookmarks may follow file identity when the old app moves to recovery,
        # even if a new chapter appears at the same pathname. Never assume a
        # bookmark inside the old bundle will retarget to the installed copy.
        if chosen.is_relative_to(installed):
            raise ValueError("Selected chapter bookmark is inside the installed app; preserve and explicitly select a stable external build first")
        chapters[str(chosen)] = resources(chosen)
    else:
        chosen = next((p for p in (bundled, adjacent) if str(p) in chapters), None)
    earlier = selected["earlierAdventure"]
    if earlier["present"]:
        earlier_path = checked(Path(earlier["path"]))
        if not earlier_path.is_dir() or earlier_path.is_relative_to(installed):
            raise ValueError("Earlier adventure selection would be lost or is unavailable")
    if build is not None:
        source = checked(build)
        actual = resources(source)
        if load(manifest) != actual:
            raise ValueError("Explicit First Signal resources do not match the independent manifest")
        chapters[str(source)] = actual
    elif chosen is not None and installed_state is not None:
        source = chosen
    else:
        raise ValueError("No preserved First Signal chapter; provide a verified build and independent manifest")
    # Deliberate chapter upgrades/save migrations are outside a native update.
    # Never silently choose among divergent builds, including an old bundle.
    expected = chapters[str(source)]
    if any(value != expected for value in chapters.values()):
        raise ValueError("First Signal resource mismatch between existing/selected/supplied chapters")
    plan = {"schema": PLAN_SCHEMA, "owner": OWNER, "hostSource": host_identity(repo),
            "installedPath": str(installed), "installedIdentity": installed_state,
            "selection": selected, "chapters": chapters, "source": str(source),
            "resources": expected, "independentManifest": file_record(manifest) if manifest else None}
    write_new(output, plan)
    return plan


def recheck(plan, repo, selection):
    if plan.get("schema") != PLAN_SCHEMA or plan.get("owner") != OWNER:
        raise ValueError("Unknown preservation plan")
    if host_identity(repo) != plan["hostSource"] or selection_evidence(selection) != plan["selection"]:
        raise ValueError("Host source or selected save owner changed during staging")
    installed = Path(plan["installedPath"])
    if installed_identity(installed) != plan["installedIdentity"]:
        raise ValueError("Installed app changed during staging")
    # Check for candidates appearing as well as previously inventoried ones.
    discovered = {str(p) for p in (installed / CHAPTER, installed.parent / "QiMonFirstSignalWeb")
                  if p.exists() or p.is_symlink()}
    if not discovered.issubset(plan["chapters"]):
        raise ValueError("Another First Signal chapter appeared during staging")
    for path, before in plan["chapters"].items():
        if resources(Path(path)) != before:
            raise ValueError("First Signal resources changed during staging")
    earlier = plan["selection"]["earlierAdventure"]
    if earlier["present"]:
        path = checked(Path(earlier["path"]))
        if not path.is_dir() or path.is_relative_to(installed):
            raise ValueError("Earlier adventure selection became unavailable during staging")


def receipt(plan):
    # Do not put authoring paths or bookmark metadata in the signed application.
    return {"schema": PLAN_SCHEMA, "owner": OWNER, "resources": plan["resources"],
            "status": "PRESERVED_BYTES_ONLY",
            "limits": "No game/save was opened. Gameplay, current-save resume, older standalone saves, and runtime integration require separate Mac evidence."}


def package(plan, repo, selection, candidate):
    recheck(plan, repo, selection)
    candidate = checked(candidate)
    source = Path(plan["source"])
    if candidate.is_relative_to(source) or source.is_relative_to(candidate) or candidate == Path(plan["installedPath"]):
        raise ValueError("Candidate must be separate from the working app and chapter")
    destination = candidate / CHAPTER
    # copytree refuses an existing destination. Links are copied as links and
    # rejected on re-inventory, never deliberately dereferenced into new assets.
    shutil.copytree(source, destination, symlinks=True, ignore=shutil.ignore_patterns(".DS_Store"))
    if resources(destination) != plan["resources"]:
        raise ValueError("Staged First Signal copy does not match preserved resources")
    recheck(plan, repo, selection)
    write_new(candidate / RECEIPT, receipt(plan))


def verify(plan, repo, selection, candidate):
    recheck(plan, repo, selection)
    candidate = checked(candidate)
    if candidate == Path(plan["installedPath"]):
        raise ValueError("Verification requires a separate staged candidate")
    for relative in ("Contents", "Contents/MacOS", "Contents/Resources"):
        if (candidate / relative).is_symlink() or not (candidate / relative).is_dir():
            raise ValueError("Candidate has missing or linked bundle directories")
    file_record(candidate / "Contents/Info.plist")
    file_record(candidate / "Contents/MacOS/ARCHiDesktop")
    info = plistlib.loads((candidate / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != OWNER["appIdentifier"]
            or info.get("CFBundleExecutable") != "ARCHiDesktop" or info.get("CFBundlePackageType") != "APPL"):
        raise ValueError("Candidate application would disconnect the existing save owner")
    if resources(candidate / CHAPTER) != plan["resources"] or load(candidate / RECEIPT) != receipt(plan):
        raise ValueError("Candidate First Signal resources/receipt changed before promotion")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    baseline = commands.add_parser("manifest", help="Inventory a separately verified working build; no runtime qualification")
    baseline.add_argument("chapter", type=Path)
    baseline.add_argument("output", type=Path)
    for name in ("capture", "package", "verify"):
        command = commands.add_parser(name)
        command.add_argument("--repo", type=Path, required=True)
        command.add_argument("--selection", type=Path, required=True)
        command.add_argument("--plan", type=Path, required=True)
        if name == "capture":
            command.add_argument("--installed-app", type=Path, required=True)
            command.add_argument("--build", type=Path)
            command.add_argument("--manifest", type=Path)
        else:
            command.add_argument("--candidate", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "manifest":
            write_new(args.output, resources(args.chapter))
        elif args.command == "capture":
            capture(args.repo, args.installed_app, args.selection, args.plan, build=args.build, manifest=args.manifest)
        else:
            operation = package if args.command == "package" else verify
            operation(load(args.plan), args.repo, args.selection, args.candidate)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, plistlib.InvalidFileException) as error:
        print(f"First Signal preflight refused: {error}. No installation is authorized by this check.", file=sys.stderr)
        return 1
    print("First Signal resource preservation checked; gameplay/save resume remains unverified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
