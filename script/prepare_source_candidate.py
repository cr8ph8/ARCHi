#!/usr/bin/env python3
"""Prepare a NEW local allowlisted candidate. Never touch a publication checkout.

Uses source_release_preflight's inventory and release/proposed editorial files.
PNG metadata is removed without changing image payload. FBX repairs use the
installed Blender parser, change one fixed-width metadata string, then compare
the entire parsed tree. No Blender/Unity application is launched by this script.
"""
from __future__ import annotations

import argparse
import importlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import types
import zlib

import source_release_preflight as preflight

EDITORIAL = preflight.RELEASE_FILES | {"package.json", "package-lock.json", "desktop/README.md", "unity/ARCHi/README.md", "arc/README.md"}


def sanitize_png(data):
    findings = preflight.scan("candidate.png", data)
    if any(row["code"] == "invalid-png" for row in findings):
        raise ValueError("Invalid PNG")
    offset, kept, removed, image_payload = 8, [], [], []
    while offset < len(data):
        size = int.from_bytes(data[offset:offset + 4], "big")
        end = offset + size + 12
        kind = data[offset + 4:offset + 8]
        raw = data[offset:end]
        if kind in {b"tEXt", b"iTXt", b"zTXt", b"eXIf"}:
            removed.append({"chunkType": kind.decode(), "bytes": len(raw)})
        else:
            kept.append(raw)
        if kind == b"IDAT":
            image_payload.append(data[offset + 8:end - 4])
        offset = end
    output = data[:8] + b"".join(kept)
    # IDAT and every non-metadata chunk are copied as complete original bytes.
    payload = b"".join(image_payload)
    return output, {"removed": removed, "idatSha256": preflight.sha(payload),
                    "scanlineSha256": preflight.sha(zlib.decompress(payload)),
                    "idatUnchanged": True, "allOtherChunksByteIdentical": True}


def load_fbx_parser(path: Path):
    """Load only the installed standalone parser and its local dependencies."""
    path = path.resolve()
    if path.name != "parse_fbx.py" or not path.is_file():
        raise ValueError("Expected an installed Blender parse_fbx.py")
    package = types.ModuleType("archi_release_fbx_parser")
    package.__path__ = [str(path.parent)]
    sys.modules[package.__name__] = package
    return importlib.import_module(package.__name__ + ".parse_fbx")


def field_nodes(node, ancestors=()):
    current = (*ancestors, node.id)
    result = []
    if current[-4:] == (b"FBXHeaderExtension", b"SceneInfo", b"Properties70", b"P"):
        if len(node.props) == 5 and node.props[0] == b"Original|ApplicationNativeFile" and node.props_type[-1:] == b"S":
            result.append(node)
    for child in node.elems:
        result.extend(field_nodes(child, current))
    return result


def compare_fbx(original, exported, old_value, new_value):
    """Every typed value/array and every child must match except one metadata value."""
    count = 0
    if original.id != exported.id or original.props_type != exported.props_type or len(original.props) != len(exported.props) or len(original.elems) != len(exported.elems):
        raise ValueError("FBX structure changed")
    for index, (before, after) in enumerate(zip(original.props, exported.props)):
        if before != after:
            if not (original.id == b"P" and original.props[0] == b"Original|ApplicationNativeFile" and index == 4
                    and before == old_value and after == new_value):
                raise ValueError("Unexpected FBX property change")
            count += 1
    for before, after in zip(original.elems, exported.elems):
        count += compare_fbx(before, after, old_value, new_value)
    return count


def sanitize_fbx(source: Path, destination: Path, parser):
    data = source.read_bytes()
    tree, version = parser.parse(str(source))
    fields = field_nodes(tree)
    if len(fields) != 1:
        raise ValueError("Expected exactly one FBX original-file metadata field")
    original = fields[0].props[-1]
    if not (preflight.PATTERNS["private-home-path"].search(original) or preflight.PATTERNS["windows-home-path"].search(original)):
        raise ValueError("Private path is outside the reviewed FBX metadata field")
    label = ("source/" + source.stem + ".blend").encode()
    if len(label) > len(original):
        raise ValueError("New FBX metadata exceeds the existing string width")
    replacement = label.ljust(len(original), b" ")
    encoded = b"S" + len(original).to_bytes(4, "little") + original
    if data.count(encoded) != 1:
        raise ValueError("FBX metadata string is not unique")
    start = data.index(encoded) + 5
    output = data[:start] + replacement + data[start + len(original):]
    preflight.write_new(destination, output)
    reparsed, exported_version = parser.parse(str(destination))
    count = compare_fbx(tree, reparsed, original, replacement)
    if version != exported_version or count != 1 or len(data) != len(output):
        raise ValueError("FBX metadata roundtrip failed")
    return output, {"field": "FBXHeaderExtension/SceneInfo/Properties70/Original|ApplicationNativeFile",
                    "fbxVersion": version, "byteOffset": start, "stringBytes": len(original),
                    "replacement": replacement.decode().rstrip(), "changedPropertyCount": count,
                    "fileLengthUnchanged": True, "allOtherBytesIdentical": True, "allOtherParsedPropertiesIdentical": True,
                    "unityImportQualified": False}


def prepare(root: Path, destination: Path, parser_path: Path | None):
    if destination.exists() or destination.is_symlink():
        raise ValueError("Candidate path already exists")
    destination = destination.resolve()
    # A new sibling/child of ignored output is allowed; no existing directory,
    # original source path, or existing public checkout can be overwritten.
    if destination.exists() or destination.is_symlink() or not destination.parent.is_dir():
        raise ValueError("Candidate needs a new path in an existing output directory")
    if destination == root or root in destination.parents and "output" not in destination.relative_to(root).parts:
        raise ValueError("In-workspace candidates must be under output")
    existing_repository = subprocess.run(["git", "-C", str(destination.parent), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if existing_repository.returncode == 0 and Path(existing_repository.stdout.strip()).resolve() != root.resolve():
        raise ValueError("Do not prepare inside another existing Git checkout")
    receipt_path = destination.parent / (destination.name + "-preparation.json")
    if receipt_path.exists() or receipt_path.is_symlink():
        raise ValueError("Candidate receipt path already exists")
    paths, problems = preflight.collect(root)
    unexpected = [row for row in problems if not (row["code"] == "REQUIRED_FILE_MISSING" and row["path"] in EDITORIAL)]
    if unexpected:
        raise ValueError("Resolve source inventory problems before copying")
    editorial_root = root / "release/proposed"
    for name in EDITORIAL:
        if preflight.linked(editorial_root, name) or not (editorial_root / name).is_file():
            raise ValueError("Required editorial proposal is missing or linked")
    snapshots = {name: (root / name).read_bytes() for name in paths}
    source_modes = {name: bool((root / name).stat().st_mode & 0o111) for name in paths}
    editorial = {name: (editorial_root / name).read_bytes() for name in EDITORIAL}
    package = json.loads(editorial["package.json"])
    version = package["version"]
    source_package = json.loads(snapshots["package.json"])
    if any(package.get(key, {}) != source_package.get(key, {}) for key in ["dependencies", "devDependencies"]):
        raise ValueError("Proposed dependency metadata is stale")
    expected_lock = json.loads(snapshots["package-lock.json"])
    expected_lock["version"] = version
    expected_lock["packages"][""]["version"] = version
    expected_lock["packages"][""]["license"] = package["license"]
    if json.loads(editorial["package-lock.json"]) != expected_lock:
        raise ValueError("Proposed dependency lock is stale")
    parser = None
    destination.mkdir()
    records, replacements = [], {}
    for relative, data in sorted({**snapshots, **editorial}.items()):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        record = {"path": relative, "sourceSha256": preflight.sha(data), "editorialProposal": relative in EDITORIAL}
        written = False
        if target.suffix == ".png":
            data, repair = sanitize_png(data)
            if repair["removed"]:
                record["pngMetadataRepair"] = repair
        if target.suffix == ".fbx" and preflight.scan(relative, data):
            if parser_path is None:
                raise ValueError("FBX metadata repair requires the installed Blender parser")
            parser = parser or load_fbx_parser(parser_path)
            data, repair = sanitize_fbx(root / relative, target, parser)
            record["fbxMetadataRepair"] = repair
            written = True
        if relative == "script/build_and_run.sh":
            content, count = re.subn(r"(<key>CFBundleShortVersionString</key><string>)[^<]+(</string>)", lambda m: m[1] + version + m[2], data.decode())
            if count != 1:
                raise ValueError("Native version adaptation must have one target")
            data = content.encode()
            record["nativeVersionCarriedForward"] = version
        if not written:
            preflight.write_new(target, data)
        if relative in snapshots:
            target.chmod(0o755 if source_modes[relative] else 0o644)
        record["exportedSha256"] = preflight.sha(data)
        if target.suffix in {".png", ".fbx"} and record["sourceSha256"] != record["exportedSha256"]:
            replacements[record["sourceSha256"]] = record["exportedSha256"]
        records.append(record)
    # Update runtime/test literal pins and asset contracts to exported bytes.
    # The historical pilot/source manifest stays unchanged and receives an
    # explicit export section below instead of rewriting its historical hashes.
    for record in records:
        relative = record["path"]
        if Path(relative).suffix not in {".swift", ".cs", ".json"} or relative == "unity/ARCHi/source-provenance.json":
            continue
        target = destination / relative
        text = target.read_text()
        for old, new in replacements.items():
            text = text.replace(old, new)
            for prefix in ["pearl-study-v1-", "lumen-pearl-v1-"]:
                text = text.replace(prefix + old[:8], prefix + new[:8])
        target.write_text(text)
    pearl = destination / "unity/ARCHi/Assets/ARCHiStudies/PearlStudyV1/asset-contract.json"
    contract = json.loads(pearl.read_text())
    contract["source"] = "desktop/Sources/ARCHiDesktop/Resources/CompanionArt/archi-pearl-study-v1.png"
    contract["publicExport"] = "Metadata removed in candidate; image payload unchanged."
    pearl.write_bytes(preflight.json_bytes(contract))
    for name in ["unity/ARCHi/Assets/Resources/KIN/provenance.json", "unity/ARCHi/Assets/Resources/Branding/provenance.json"]:
        target = destination / name
        value = json.loads(target.read_text())
        for row in value.get("assets", []):
            if "asset" in row and (target.parent / row["asset"]).is_file():
                row["bytes"] = (target.parent / row["asset"]).stat().st_size
        target.write_bytes(preflight.json_bytes(value))
    provenance = destination / "unity/ARCHi/source-provenance.json"
    value = json.loads(provenance.read_text())
    value["candidateExport"] = {"historicalHashesPreserved": True, "metadataRepairs": [{"path": row["path"], "sourceSha256": row["sourceSha256"], "exportedSha256": row["exportedSha256"]} for row in records if "pngMetadataRepair" in row or "fbxMetadataRepair" in row], "qualification": "Local source candidate; metadata transformations are not rights or release approval."}
    provenance.write_bytes(preflight.json_bytes(value))
    changed = [name for name, data in snapshots.items()
               if preflight.linked(root, name) or (root / name).read_bytes() != data
               or bool((root / name).stat().st_mode & 0o111) != source_modes[name]]
    changed_editorial = [name for name, data in editorial.items()
                        if preflight.linked(editorial_root, name) or (editorial_root / name).read_bytes() != data]
    final_paths, _ = preflight.collect(root)
    if changed or changed_editorial or final_paths != paths:
        raise ValueError("Source writers changed the snapshot; retain this candidate for inspection and repeat in a new path")
    # Asset metadata repair must never silently invalidate an included checker.
    # Keep its reviewed pins exact; do not repin on the publisher's machine.
    if preflight.replay_dependency_checks(destination, {row["path"] for row in records}):
        raise ValueError("Export changed or omitted a pinned ARC replay dependency")
    for record in records:
        record["exportedSha256"] = preflight.sha((destination / record["path"]).read_bytes())
    findings = [finding for row in records for finding in preflight.scan(row["path"], (destination / row["path"]).read_bytes())]
    manifest = "".join(f"{row['exportedSha256']}  {row['path']}\n" for row in sorted(records, key=lambda row: row["path"]))
    preflight.write_new(destination / "SOURCE_SHA256SUMS", manifest.encode())
    receipt = {"schema": "archi-local-source-candidate/v1", "candidate": str(destination), "status": "SCAN_BLOCKED" if findings else "PREPARED_FOR_REVIEW",
               "sourceStableDuringCopy": True, "editorialStableDuringCopy": True,
               "sourceExecutableModesStable": True, "sourceFileCount": len(records), "records": records,
               "developmentInputHashes": {name: preflight.sha(data) for name, data in sorted(snapshots.items())},
               "scanFindings": findings, "manifestSha256": preflight.sha(manifest.encode()),
               "preparationToolSha256": preflight.sha(Path(__file__).read_bytes()),
               "inventoryToolSha256": preflight.sha(Path(preflight.__file__).read_bytes()),
               "fbxParserSha256": preflight.sha(parser_path.read_bytes()) if parser else None,
               "qualification": "No Git init/commit, package installation, native/Unity build, app launch, publication or redistribution approval performed."}
    preflight.write_new(receipt_path, preflight.json_bytes(receipt))
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=preflight.ROOT)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--fbx-parser", type=Path)
    args = parser.parse_args()
    try:
        result = prepare(args.root.resolve(), args.destination, args.fbx_parser)
        print(json.dumps({key: result[key] for key in ["status", "candidate", "sourceFileCount", "manifestSha256"]}, indent=2))
        return 1 if result["scanFindings"] else 0
    except (ValueError, OSError, TypeError, KeyError) as error:
        print(f"Candidate preparation stopped ({type(error).__name__}). Existing source was preserved; inspect inputs and any partial NEW candidate.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
