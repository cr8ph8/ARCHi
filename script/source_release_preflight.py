#!/usr/bin/env python3
"""Inventory the ARCHi source distribution and fail closed on release blockers.

Read-only unless --report or --manifest names a NEW output file. Never copies a
source tree, publishes, installs dependencies, builds, signs, or reads profiles.
The bounded scanner reports locations/categories, never matching secret values.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[1]
ARC_REPLAY_FILES = {
    "scripts/arc-replay.mjs", "scripts/arc-replay-worker.mjs", "scripts/arc-replay.test.mjs",
    "scripts/arc-replay-config.json", "scripts/arc-replay-pins.json",
}
RELEASE_FILES = {"LICENSE", "ASSET_ATTRIBUTION.md", "THIRD_PARTY_NOTICES.md", "README.md", "docs/ALPHA_VALIDATION.md"}
RELEASE_FILES.add("docs/native-qwen.md")
EXACT = RELEASE_FILES | ARC_REPLAY_FILES | {
    ".gitignore", ".postcssrc.json", "index.html", "tsconfig.json", "package.json", "package-lock.json",
    "desktop/Package.swift", "desktop/README.md", "arc/README.md", "arc/tsconfig.json",
    "arc/fixtures/manifest.json", "arc/fixtures/golden/smoke-evidence-v1.json",
    "arc/fixtures/smoke/synthetic-increment-001.json", "arc/fixtures/portable/smoke-evaluation-v1.json",
    "arc/fixtures/portable/third-rate-evaluation-v1.json", "arc/fixtures/golden/third-rate-evidence-v1.json",
    "docs/native-arc-capabilities.md", "docs/native-arc-solving.md", "docs/native-arc-workspace-integration.md", "docs/native-arc-qwen-proposals.md", "docs/active-arc-assistant.md", "docs/active-arc3.md", "docs/active-document-work.md", "script/test_arc3_bridge.py", "docs/native-marketplace.md", "script/build_and_run.sh",
    "script/build_unity_port.sh", "script/source_release_preflight.py",
    "script/prepare_source_candidate.py", "script/archive_source_candidate.py",
    "scripts/tests/test_prepare_source_candidate.py", "scripts/tests/test_archive_source_candidate.py",
    "scripts/tests/test_source_release_preflight.py", "scripts/archi-reactor-mcp.py",
    "scripts/boundary-text.mjs", "scripts/boundary-text.test.mjs", "scripts/build-pwa.mjs",
    "scripts/episode-trace.mjs", "scripts/episode-trace.test.mjs", "scripts/pwa-contract.mjs",
    "scripts/pwa-contract.test.mjs", "scripts/setup-reactor-runtime.sh",
    "scripts/tests/test_archi_reactor_mcp.py", "scripts/tests/test_reactor_worker.py",
    "scripts/export-arena-reference.mjs", "scripts/export-proto-recipe.mjs",
    "unity/ARCHi/README.md", "unity/ARCHi/.gitignore", "unity/ARCHi/source-provenance.json",
    "unity/ARCHi/Packages/manifest.json", "unity/ARCHi/Packages/packages-lock.json",
    "marketplace/.gitignore", "marketplace/README.md", "marketplace/API.md",
    "docs/unity-arena-and-creator-marketplace-2026-09-16.md",
}
SCOPES = {
    "desktop/Sources/ARCHiDesktop": {".swift"},
    "desktop/Tests/ARCHiDesktopTests": {".swift"},
    "desktop/Sources/ARCHiDesktop/Resources/CompanionArt": {".png"},
    "desktop/Sources/ARCHiDesktop/Resources/Branding": {".png", ".icns"},
    "desktop/Sources/ARCHiDesktop/Resources/ARC3Bridge": {".py", ".txt"},
    "desktop/Sources/ARCHiDesktop/Resources/ReactorBridge": {".py", ".txt"},
    "src": {".ts", ".css"}, "pwa": {".svg", ".png", ".js", ".webmanifest"},
    "arc/src": {".ts"}, "arc/test": {".ts"},
    "marketplace": {".py", ".md"},
    "unity/ARCHi/Assets": {".cs", ".json", ".mat", ".asset", ".unity", ".uxml", ".uss", ".png", ".meta", ".asmdef", ".shader", ".shadervariants", ".tss", ".fbx"},
    "unity/ARCHi/ProjectSettings": {".asset", ".json", ".txt"},
    "unity/ARCHi/Packages/com.coplaydev.unity-mcp": {".cs", ".json", ".md", ".meta", ".asmdef", ".uss", ".uxml"},
}
EXCLUDED = {".git", ".codex", ".playwright-cli", "__pycache__", "node_modules", "dist", "output", "outputs", "tmp", ".build", ".swiftpm", "Library", "Temp", "Logs", "UserSettings", "Builds", "ArtSources", "private-archive", "test-results", "playwright-report"}
EXCLUDED_PREFIXES = {"marketplace/data"}
EXCLUDED_SUFFIXES = {".pyc", ".log", ".blend", ".blend1", ".dylib", ".dll", ".exe", ".zip", ".sqlite", ".sqlite3", ".sqlite3-journal", ".sqlite3-wal", ".sqlite3-shm", ".db", ".pem", ".key", ".p12", ".mobileprovision"}
ASSET_SUFFIXES = {".png", ".icns", ".fbx", ".svg"}
CHECK_NAMES = {"web-source", "native-source", "unity-source", "native-unity-marketplace-acceptance",
               "creator-marketplace-service", "native-creator-marketplace-acceptance"}
PATTERNS = {
    "private-home-path": re.compile(rb"/" + rb"Users/(?!Shared(?:/|\b))[^/\s\x00\"']+/"),
    "windows-home-path": re.compile(rb"[A-Za-z]:[\\/]Users[\\/][^\\/\s\x00\"']+[\\/]"),
    "github-token": re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "provider-key": re.compile(rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{35,}"),
    "private-key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "aws-access-key": re.compile(rb"\bAKIA[A-Z0-9]{16}\b"),
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode()


def issue(code: str, path: str | None = None, **details) -> dict:
    return {"code": code, **({"path": path} if path else {}), **details}


def linked(root: Path, relative: str) -> bool:
    path = root
    for part in Path(relative).parts:
        path = path / part
        if path.is_symlink():
            return True
    return False


def collect(root: Path, exact=None, scopes=None):
    """Traverse only declared roots; never descend into links or excluded trees."""
    exact = EXACT if exact is None else exact
    scopes = SCOPES if scopes is None else scopes
    allowed, observed, blockers = set(), set(), []
    for relative in sorted(exact):
        if linked(root, relative):
            blockers.append(issue("SOURCE_SYMLINK", relative))
        elif (root / relative).is_file():
            allowed.add(relative)
        else:
            blockers.append(issue("REQUIRED_FILE_MISSING", relative))
    for relative, suffixes in scopes.items():
        if linked(root, relative):
            blockers.append(issue("SOURCE_SYMLINK", relative))
            continue
        directory = root / relative
        if not directory.is_dir():
            blockers.append(issue("REQUIRED_SCOPE_MISSING", relative))
            continue
        for current, dirs, files in os.walk(directory, followlinks=False):
            kept = []
            for name in sorted(dirs):
                path = Path(current) / name
                if name in EXCLUDED or path.relative_to(root).as_posix() in EXCLUDED_PREFIXES:
                    continue
                if path.is_symlink():
                    blockers.append(issue("SOURCE_SYMLINK", path.relative_to(root).as_posix()))
                else:
                    kept.append(name)
            dirs[:] = kept
            for name in sorted(files):
                path = Path(current) / name
                rel = path.relative_to(root).as_posix()
                if name == ".DS_Store" or path.suffix in {".pyc", ".log"}:
                    continue
                if path.is_symlink():
                    blockers.append(issue("SOURCE_SYMLINK", rel))
                    continue
                observed.add(rel)
                if path.suffix in suffixes and not name.startswith(".env") and path.suffix not in EXCLUDED_SUFFIXES:
                    allowed.add(rel)
    blockers += [issue("UNREVIEWED_FILE_KIND", name) for name in sorted(observed - allowed)]
    for name in sorted(allowed):
        if name.startswith("unity/ARCHi/Assets/") and not name.endswith(".meta") and name + ".meta" not in allowed:
            blockers.append(issue("UNITY_META_MISSING", name + ".meta"))
        # Verify literal fixture dependencies without discovering or opening
        # their contents outside the reviewed source set. This is deliberately
        # bounded to JSON imports and native ARC fixture literals, not a claim
        # to resolve dynamic runtime paths or arbitrary language dependencies.
        dependencies = set()
        if Path(name).suffix == ".ts":
            for reference in re.findall(rb"\bfrom\s*['\"]([^'\"\r\n]+\.json)['\"]", (root / name).read_bytes()):
                reference = reference.decode("utf-8")
                if reference.startswith("."):
                    dependencies.add(posixpath.normpath(posixpath.join(posixpath.dirname(name), reference)))
        elif Path(name).suffix == ".swift":
            dependencies.update(reference.decode("utf-8") for reference in
                                re.findall(rb'"(arc/fixtures/[^"\r\n]+\.json)"', (root / name).read_bytes()))
        for dependency in sorted(dependencies - allowed):
            blockers.append(issue("SOURCE_FIXTURE_DEPENDENCY_MISSING", name, dependency=dependency))
    blockers.extend(replay_dependency_checks(root, allowed))
    return sorted(allowed), sorted({json.dumps(x, sort_keys=True): x for x in blockers}.values(), key=lambda x: (x["code"], x.get("path", "")))



def replay_dependency_checks(root: Path, allowed: set[str]) -> list[dict]:
    """Retain the exact offline checker closure without following pin paths outside the allowlist.

    These are source-integrity checks, not a replay pass or authorization to
    regenerate its reviewed runtime/environment pins for the publishing host.
    """
    manifest = "scripts/arc-replay-pins.json"
    if manifest not in allowed:
        return []
    try:
        data = (root / manifest).read_bytes()
        if len(data) > 131072:
            raise ValueError()
        value = json.loads(data)
        pins = value.get("files") if isinstance(value, dict) else None
        if value.get("schema") != "archi-arc-checker-replay-pins/v1" or not isinstance(pins, dict) or not pins:
            raise ValueError()
        for relative, digest in pins.items():
            if (not isinstance(relative, str) or not relative or Path(relative).is_absolute()
                    or relative != posixpath.normpath(relative) or ".." in Path(relative).parts
                    or "\\" in relative or not isinstance(digest, str)
                    or re.fullmatch(r"sha256:[0-9a-f]{64}", digest) is None):
                raise ValueError()
    except (ValueError, TypeError, AttributeError):
        return [issue("SOURCE_REPLAY_PINS_INVALID", manifest)]
    blockers = []
    for relative, digest in sorted(pins.items()):
        if relative not in allowed:
            blockers.append(issue("SOURCE_REPLAY_DEPENDENCY_MISSING", manifest, dependency=relative))
        elif linked(root, relative) or "sha256:" + sha((root / relative).read_bytes()) != digest:
            blockers.append(issue("SOURCE_REPLAY_PIN_MISMATCH", relative))
    return blockers


def scan(relative: str, data: bytes) -> list[dict]:
    findings = []
    # Raw-byte patterns also cover ordinary plaintext paths inside FBX assets.
    # Compressed or encoded arbitrary content is outside this scanner's claim.
    for category, pattern in PATTERNS.items():
        for match in pattern.finditer(data):
            findings.append(issue(category, relative, byteOffset=match.start()))
    if Path(relative).suffix == ".png":
        try:
            if data[:8] != b"\x89PNG\r\n\x1a\n":
                raise ValueError()
            offset, final = 8, False
            while offset < len(data):
                if offset + 12 > len(data) or final:
                    raise ValueError()
                size = int.from_bytes(data[offset:offset + 4], "big")
                end = offset + size + 12
                if end > len(data):
                    raise ValueError()
                kind = data[offset + 4:offset + 8]
                payload = data[offset + 8:end - 4]
                if zlib.crc32(kind + payload) & 0xffffffff != int.from_bytes(data[end - 4:end], "big"):
                    raise ValueError()
                if kind in {b"tEXt", b"iTXt", b"zTXt"}:
                    # Every text chunk requires review, including compressed text.
                    findings.append(issue("png-text-metadata", relative, byteOffset=offset, chunkType=kind.decode()))
                if kind == b"eXIf":
                    findings.append(issue("png-exif-metadata", relative, byteOffset=offset))
                final = kind == b"IEND"
                offset = end
            if not final:
                raise ValueError()
        except ValueError:
            findings.append(issue("invalid-png", relative))
    return findings


def git_state(root: Path) -> dict:
    def run(*args):
        return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL)
    try:
        if Path(run("rev-parse", "--show-toplevel").decode().strip()).resolve() != root.resolve():
            return {"isRootRepository": False}
        statuses = run("status", "--porcelain=v1", "-z", "--untracked-files=all").split(b"\0")
        tracked = run("ls-files", "-z").decode().split("\0")
        return {"isRootRepository": True, "head": run("rev-parse", "HEAD").decode().strip(),
                "branch": run("branch", "--show-current").decode().strip(), "clean": not any(statuses),
                "statusRecordCount": len([x for x in statuses if x]), "tracked": set(tracked) - {""}}
    except (OSError, subprocess.CalledProcessError):
        return {"isRootRepository": False}


def validate_review(review, digest: str, assets: list[dict], root: Path) -> list[dict]:
    if not isinstance(review, dict):
        return [issue("RELEASE_REVIEW_MISSING")]
    blockers = []
    if review.get("sourceInventoryDigest") != digest:
        blockers.append(issue("REVIEW_SOURCE_DIGEST_MISMATCH"))
    if review.get("publicationScopeReviewed") is not True:
        blockers.append(issue("PUBLICATION_SCOPE_UNREVIEWED"))
    approvals = {row.get("path"): row for row in review.get("assetRights", []) if isinstance(row, dict)}
    for asset in assets:
        row = approvals.get(asset["path"], {})
        if not (row.get("sha256") == asset["sha256"] and row.get("status") == "approved"
                and row.get("license") and row.get("authority")):
            blockers.append(issue("ASSET_REDISTRIBUTION_UNREVIEWED", asset["path"]))
    checks = {row.get("name"): row for row in review.get("checks", []) if isinstance(row, dict)}
    for name in sorted(CHECK_NAMES):
        row = checks.get(name, {})
        if not (row.get("status") == "passed" and type(row.get("exitCode")) is int and row["exitCode"] == 0
                and row.get("sourceInventoryDigest") == digest and row.get("command") and row.get("limitations") is not None):
            blockers.append(issue("CHECK_UNQUALIFIED", check=name))
            continue
        evidence = row.get("evidencePath")
        if not isinstance(evidence, str) or not evidence:
            blockers.append(issue("CHECK_EVIDENCE_MISSING", check=name))
            continue
        path = Path(evidence)
        if not path.is_absolute():
            path = root / path
        if path.is_symlink() or not path.is_file() or sha(path.read_bytes()) != row.get("evidenceSha256"):
            blockers.append(issue("CHECK_EVIDENCE_MISMATCH", check=name))
    return blockers


def audit(root: Path, baseline: Path | None = None, review=None, exact=None, scopes=None) -> dict:
    paths, blockers = collect(root, exact, scopes)
    inventory, findings = [], []
    for relative in paths:
        path = root / relative
        data = path.read_bytes()
        inventory.append({"path": relative, "sha256": sha(data), "bytes": len(data), "executable": bool(path.stat().st_mode & 0o111)})
        findings.extend(scan(relative, data))
    digest = sha(json_bytes(inventory))
    manifest = "".join(f"{row['sha256']}  {row['path']}\n" for row in inventory)
    state = git_state(root)
    tracked = state.pop("tracked", set())
    if not state.get("isRootRepository"):
        blockers.append(issue("CANDIDATE_GIT_IDENTITY_MISSING"))
    elif not state.get("clean"):
        blockers.append(issue("WORKTREE_DIRTY", count=state["statusRecordCount"]))
    untracked = [name for name in paths if name not in tracked]
    if untracked:
        blockers.append(issue("SOURCE_FILES_NOT_TRACKED", count=len(untracked)))
    # A public history must contain only reviewed source, even when an excluded
    # file is currently ignored. No excluded file contents are opened here.
    outside = [name for name in sorted(tracked) if name not in paths and name != "SOURCE_SHA256SUMS"]
    if outside:
        blockers.append(issue("TRACKED_FILES_OUTSIDE_ALLOWLIST", count=len(outside), paths=outside))
    assets = []
    for row in inventory:
        if Path(row["path"]).suffix in ASSET_SUFFIXES:
            old = baseline / row["path"] if baseline else None
            assets.append({**row, "baseline": ("unchanged" if old and not linked(baseline, row["path"]) and old.is_file() and sha(old.read_bytes()) == row["sha256"] else "new-or-changed") if baseline else "not-compared"})
    provenance = [row for row in inventory if "provenance" in row["path"] or "asset-contract" in row["path"]]
    checksums = root / "SOURCE_SHA256SUMS"
    if checksums.is_symlink() or not checksums.is_file():
        blockers.append(issue("SOURCE_CHECKSUMS_MISSING"))
    elif checksums.read_text() != manifest:
        blockers.append(issue("SOURCE_CHECKSUMS_STALE"))
    package = root / "package.json"
    if package.is_file() and not linked(root, "package.json"):
        value = json.loads(package.read_text())
        if value.get("license") != "MIT":
            blockers.append(issue("PACKAGE_LICENSE_METADATA_MISSING", "package.json"))
        for name, command in value.get("scripts", {}).items():
            for script in re.findall(r"\bnode\s+(scripts/[^\s;&]+)", command):
                if script not in paths:
                    blockers.append(issue("PACKAGE_COMMAND_EXCLUDED_INPUT", script, command=name))
        build = root / "script/build_and_run.sh"
        if "script/build_and_run.sh" in paths:
            version = re.search(r"<key>CFBundleShortVersionString</key><string>([^<]+)</string>", build.read_text())
            if version and version[1] != value.get("version"):
                blockers.append(issue("PACKAGE_NATIVE_VERSION_MISMATCH", "script/build_and_run.sh"))
    blockers.extend(validate_review(review, digest, assets, root))
    if findings:
        blockers.append(issue("BOUNDED_SCAN_FINDINGS", count=len(findings)))
    # Ensure no writer changed inventoried bytes or source-set membership during
    # the audit. Run again after writers finish before using any release receipt.
    final_paths, _ = collect(root, exact, scopes)
    changed = [row["path"] for row in inventory if linked(root, row["path"]) or not (root / row["path"]).is_file() or sha((root / row["path"]).read_bytes()) != row["sha256"]]
    if changed or final_paths != paths:
        blockers.append(issue("SOURCE_CHANGED_DURING_AUDIT", paths=changed, membershipChanged=final_paths != paths))
    return {"schema": "archi-source-release-preflight/v1", "status": "BLOCKED" if blockers else "PREFLIGHT_PASS",
            "sourceReleaseReady": not blockers, "publicationAuthorized": False, "notarizedAppReady": False,
            "root": str(root), "git": state, "sourceInventoryDigest": digest, "sourceFileCount": len(inventory),
            "sourceBytes": sum(row["bytes"] for row in inventory), "inventory": inventory, "assets": assets,
            "provenanceFiles": provenance, "blockers": blockers, "scanFindings": findings,
            "exclusions": sorted(EXCLUDED), "excludedPrefixes": sorted(EXCLUDED_PREFIXES),
            "excludedSuffixes": sorted(EXCLUDED_SUFFIXES),
            "scanLimit": "Declared source roots only; strong raw-byte patterns and PNG text/EXIF. Not a complete secret, copyright, metadata, Git-history, dependency or security audit.",
            "checksums": manifest, "checksumSha256": sha(manifest.encode())}


def write_new(path: Path, data: bytes) -> None:
    # Refuse overwrites, including dangling links. Callers create output parents.
    if not path.parent.is_dir():
        raise ValueError("Output parent must already exist")
    with path.open("xb") as file:
        file.write(data)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--baseline", type=Path, help="Optional prior public SOURCE checkout; read-only asset comparison")
    parser.add_argument("--review", type=Path, help="Digest-bound completed source release review JSON")
    parser.add_argument("--report", type=Path, help="Write full local JSON to a new file")
    parser.add_argument("--manifest", type=Path, help="Write candidate checksums to a new file; not an approval")
    args = parser.parse_args(argv)
    try:
        review = json.loads(args.review.read_text()) if args.review else None
        report = audit(args.root.resolve(), args.baseline.resolve() if args.baseline else None, review)
        for output in [args.report, args.manifest]:
            if output and (output.exists() or output.is_symlink()):
                raise ValueError("Output already exists; choose a new output path")
        if args.report:
            write_new(args.report, json_bytes(report))
        if args.manifest:
            write_new(args.manifest, report["checksums"].encode())
        print(json.dumps({key: report[key] for key in ["status", "sourceReleaseReady", "sourceFileCount", "sourceInventoryDigest"]}, indent=2))
        print(json.dumps({"blockerCounts": dict(sorted(Counter(row["code"] for row in report["blockers"]).items())), "scanFindingCounts": dict(sorted(Counter(row["code"] for row in report["scanFindings"]).items())), "fbxAssetCount": sum(row["path"].endswith(".fbx") for row in report["assets"])}, indent=2))
        return 1 if report["blockers"] else 0
    except (ValueError, OSError, TypeError, KeyError) as error:
        # Do not print source/credential values from parse errors.
        print(f"Preflight could not complete ({type(error).__name__}). Check paths, JSON shape and new output destinations.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
