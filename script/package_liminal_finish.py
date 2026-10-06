#!/usr/bin/env python3
"""Validate/copy the separately qualified v11 display mapping into new app stages.

The authenticated v008 package is validated by package_liminal_v008.py before
this child is added. Neither source samples nor source app bundles are modified.
"""
import argparse
import math
from pathlib import Path
import plistlib
import re
import shutil
import struct

from liminal_v008_validate import read_json, sha256


EXPECTED_MANIFEST_SHA256 = "392f3f6aae7a6f550b417cf75a92e25071be37851489ccf19bfbebb4d20becdf"
REVISION = "liminal-internal-gold/v11"
COUNT, STRIDE = 200000, 16
DISPLAY_METADATA = {
    "byteOrder": "little", "coordinateSpace": "houdini-sop-local",
    "fields": ["float32 directionX", "float32 directionY", "float32 directionZ", "uint32 flags"],
    "flagBits": {"seed": 1, "trueResidual": 2, "ballResidual": 4, "trueTail": 8},
    "lodPrefixes": [50000, 100000, 200000],
    "presentation": {"emissionGain": .5, "exposure": -.5, "radiusGain": 2},
    "motion": {"curledFrom": 60, "curledThrough": 72, "orbFrom": 108, "standingThrough": 24,
               "sourceFrameSampling": "nearest-half-up", "exactHoudiniMotionParity": False,
               "displayInterpolation": "smoothstep between authored display endpoint corrections"},
}


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(value):
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def regular_file(path, size=None):
    require(path.is_file() and not path.is_symlink(), f"Not a regular file: {path}")
    require(size is None or path.stat().st_size == size, f"Incorrect file size: {path}")


def validate_finish(finish, source):
    finish, source = Path(finish), Path(source)
    require(digest(EXPECTED_MANIFEST_SHA256), "The v11 finish has not been pinned for packaging")
    require(finish.is_dir() and not finish.is_symlink(), "Finish must be a regular directory")
    require(source.is_dir() and not source.is_symlink(), "Base package must be a regular directory")
    entries = list(finish.rglob("*"))
    require({p.relative_to(finish).as_posix() for p in entries} == {"manifest.json", "annotations.bin"},
            "Unexpected v11 finish files")
    manifest_path = finish / "manifest.json"
    regular_file(manifest_path)
    require(manifest_path.stat().st_size <= 65536, "Oversized finish manifest")
    require(sha256(manifest_path) == EXPECTED_MANIFEST_SHA256, "Unqualified finish manifest")
    manifest = read_json(manifest_path)
    require(set(manifest) == {"schemaVersion", "revision", "sourceManifestSHA256", "lodSHA256",
                             "pointCount", "stride", "annotations", "blenderSHA256"} | set(DISPLAY_METADATA),
            "Wrong finish schema")
    require(all(manifest[k] == v for k, v in DISPLAY_METADATA.items()), "Wrong finish display contract")
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1
            and manifest["revision"] == REVISION, "Wrong finish revision")
    require(type(manifest["pointCount"]) is int and manifest["pointCount"] == COUNT
            and type(manifest["stride"]) is int and manifest["stride"] == STRIDE, "Wrong finish layout")
    require(all(digest(manifest[k]) for k in ("sourceManifestSHA256", "lodSHA256", "blenderSHA256")),
            "Invalid finish provenance digests")
    source_manifest = source / "manifest.json"
    regular_file(source_manifest)
    require(source_manifest.stat().st_size <= 1024 ** 2, "Oversized source manifest")
    require(sha256(source_manifest) == manifest["sourceManifestSHA256"], "Finish belongs to another base package")
    source_data = read_json(source_manifest)
    require(source_data["lod"]["ids"]["sha256"] == manifest["lodSHA256"], "Finish belongs to another ranked LOD")
    reference = manifest["annotations"]
    require(isinstance(reference, dict) and set(reference) == {"file", "sha256", "bytes"}
            and reference["file"] == "annotations.bin" and digest(reference["sha256"])
            and type(reference["bytes"]) is int and reference["bytes"] == COUNT * STRIDE,
            "Wrong finish annotation reference")
    annotations = finish / "annotations.bin"
    regular_file(annotations, COUNT * STRIDE)
    require(sha256(annotations) == reference["sha256"], "Finish annotation bytes changed")
    for x, y, z, flags in struct.iter_unpack("<3fI", annotations.read_bytes()):
        require(all(math.isfinite(v) for v in (x, y, z)) and flags <= 15, "Invalid finish annotation")
        require(abs(math.sqrt(x*x + y*y + z*z) - 1) <= .0001, "Invalid annotation direction")
        # Every rank retains a bounded direction. Rendering reads it only for
        # Seed flags; non-Seed directions are inert display metadata.
        require(not flags & 1 or flags == 1, "Seed flag must be exclusive")
    return EXPECTED_MANIFEST_SHA256


def validate_player(player, finish, source, allow_light=False):
    expected = validate_finish(finish, source)
    player = Path(player)
    plist = player / "Contents/Info.plist"
    regular_file(plist)
    with plist.open("rb") as stream:
        info = plistlib.load(stream)
    version = 7 if allow_light else 6
    require(type(info.get("ARCHiLiminalPointAssetVersion")) is int
            and info["ARCHiLiminalPointAssetVersion"] == version,
            f"Finished candidate requires player capability {version}; capability 7 needs explicit light packaging")
    require(info.get("ARCHiLiminalPointFinishSHA256") == expected, "Player finish capability digest does not match")
    embedded = player / "Contents/Resources/Data/StreamingAssets/LiminalV008/finish-v11"
    require(validate_finish(embedded, source) == expected, "Player embeds another finish")
    return expected


def package_finish(finish, source, native_resources, unity_streaming_assets):
    expected = validate_finish(finish, source)
    targets = [Path(native_resources) / "LiminalV008/finish-v11",
               Path(unity_streaming_assets) / "LiminalV008/finish-v11"]
    # Validate both prospective destinations before any copy; never replace one.
    for target in targets:
        require(target.parent.is_dir() and not target.parent.is_symlink(), "Base asset must be packaged first")
        if target.exists() or target.is_symlink():
            require(validate_finish(target, target.parent) == expected, "Stage contains a different finish")
    for target in targets:
        if not target.exists():
            shutil.copytree(finish, target, symlinks=False)
        require(validate_finish(target, target.parent) == expected, "Copied finish bytes changed")
    # Both source and copied manifests/binaries were individually authenticated.
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)
    check = subparsers.add_parser("check-player")
    check.add_argument("--allow-light", action="store_true")
    for name in ("finish", "source", "player"):
        check.add_argument(name, type=Path)
    package = subparsers.add_parser("package")
    for name in ("finish", "source", "native_resources", "unity_streaming_assets"):
        package.add_argument(name, type=Path)
    args = vars(parser.parse_args())
    mode = args.pop("mode")
    print(validate_player(**args) if mode == "check-player" else package_finish(**args))


if __name__ == "__main__":
    main()
