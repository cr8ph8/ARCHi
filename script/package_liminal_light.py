#!/usr/bin/env python3
"""Pin and package reviewed v12 surface light separately from source samples.

The base point-package gate and v11 finish gate remain independent. This tool
copies only into already prepared stages and never changes the source player.
"""
import argparse
import math
from pathlib import Path
import plistlib
import shutil
import struct

from liminal_v008_validate import read_json, sha256
from package_liminal_finish import digest, regular_file, require, validate_finish

EXPECTED_MANIFEST_SHA256 = "451164aa6eee794ed2bcf4729ab6ef3cb408889ed318fd7239cb76ce119e7c29"
STYLE = "liminal-light-flow/v12"
REVISION = "liminal-surface-light/v12"
METADATA = {
    "coordinateSpace": "houdini-sop-local", "pathCount": 32, "knotsPerPath": 12,
    "interpolation": {"type": "uniform-catmull-rom", "subdivisions": 4,
                      "duplicatedEndpoints": True, "segmentsPerPose": 1408,
                      "poseWeights": "existing v11 smoothstep finish weights"},
    "rendering": {"widthMeaning": "full diameter in native units", "colorSpace": "linear-rgb",
                  "clockSeconds": 4, "uniformBreathAmplitude": .006, "knowledgeAuthority": False},
}


def finite(value, minimum, maximum):
    return type(value) in (int, float) and math.isfinite(value) and minimum <= value <= maximum


def validate_light(light, source, finish):
    light, source = Path(light), Path(source)
    require(digest(EXPECTED_MANIFEST_SHA256), "The v12 light has not been pinned for packaging")
    require(light.is_dir() and not light.is_symlink(), "Light must be a regular directory")
    require({p.relative_to(light).as_posix() for p in light.rglob("*")} == {"manifest.json", "curves.json"},
            "Unexpected v12 light files")
    path = light / "manifest.json"
    regular_file(path)
    require(0 < path.stat().st_size <= 65536, "Oversized light manifest")
    require(sha256(path) == EXPECTED_MANIFEST_SHA256, "Unqualified light manifest")
    manifest = read_json(path)
    require(set(manifest) == {"schemaVersion", "revision", "sourceManifestSHA256", "finishManifestSHA256",
                             "lodSHA256", "sourceBlenderSHA256", "curves"} | set(METADATA), "Wrong light schema")
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1
            and manifest["revision"] == REVISION, "Wrong light revision")
    require(all(manifest[k] == v for k, v in METADATA.items()), "Wrong light presentation contract")
    require(all(digest(manifest[k]) for k in ("sourceManifestSHA256", "finishManifestSHA256", "lodSHA256", "sourceBlenderSHA256")),
            "Invalid light provenance")
    require(validate_finish(finish, source) == manifest["finishManifestSHA256"], "Light belongs to another finish")
    source_manifest = source / "manifest.json"
    regular_file(source_manifest)
    require(source_manifest.stat().st_size <= 1048576 and sha256(source_manifest) == manifest["sourceManifestSHA256"],
            "Light belongs to another base package")
    source_data = read_json(source_manifest)
    require(source_data["lod"]["ids"]["sha256"] == manifest["lodSHA256"], "Light belongs to another ranked LOD")
    ids_path = source / "lod-ids.bin"
    require(source_data["lod"]["ids"]["file"] == "lod-ids.bin", "Unexpected LOD filename")
    regular_file(ids_path, 800000)
    require(sha256(ids_path) == manifest["lodSHA256"], "Ranked IDs changed")
    ids = set(struct.unpack("<50000I", ids_path.read_bytes()[:200000]))
    require(len(ids) == 50000 and all(i < 800000 for i in ids), "Invalid low-detail IDs")
    reference = manifest["curves"]
    require(isinstance(reference, dict) and set(reference) == {"file", "sha256", "bytes"}
            and reference["file"] == "curves.json" and digest(reference["sha256"])
            and type(reference["bytes"]) is int and 2 <= reference["bytes"] <= 524288, "Wrong curves reference")
    curves_path = light / "curves.json"
    regular_file(curves_path, reference["bytes"])
    require(sha256(curves_path) == reference["sha256"], "Curve bytes changed")
    curves = read_json(curves_path)
    require(set(curves) == {"schemaVersion", "paths"} and type(curves["schemaVersion"]) is int
            and curves["schemaVersion"] == 1 and isinstance(curves["paths"], list)
            and len(curves["paths"]) == 32, "Wrong curve layout")
    for index, curve in enumerate(curves["paths"]):
        require(isinstance(curve, dict) and set(curve) == {"id", "width", "color", "intensity", "trueKnots", "ballKnots", "seedKnots"},
                "Wrong curve fields")
        require(type(curve["id"]) is int and curve["id"] == index and finite(curve["width"], .003, .006)
                and finite(curve["intensity"], .5, 1.5), "Invalid curve appearance")
        require(isinstance(curve["color"], list) and len(curve["color"]) == 3
                and all(finite(v, 0, 1) for v in curve["color"]), "Invalid curve color")
        for field in ("trueKnots", "ballKnots", "seedKnots"):
            knots = curve[field]
            require(isinstance(knots, list) and len(knots) == 12, "Wrong knot count")
            for knot in knots:
                require(isinstance(knot, dict) and set(knot) == {"position", "sourceID"}
                        and type(knot["sourceID"]) is int and knot["sourceID"] in ids, "Unqualified knot ID")
                require(isinstance(knot["position"], list) and len(knot["position"]) == 3
                        and all(finite(v, -8, 8) for v in knot["position"]), "Invalid knot position")
    return EXPECTED_MANIFEST_SHA256


def validate_player(player, light, source, finish):
    expected = validate_light(light, source, finish)
    player = Path(player)
    plist = player / "Contents/Info.plist"
    regular_file(plist)
    with plist.open("rb") as stream:
        info = plistlib.load(stream)
    require(type(info.get("ARCHiLiminalPointAssetVersion")) is int and info["ARCHiLiminalPointAssetVersion"] == 7,
            "Light candidate requires player capability 7")
    require(info.get("ARCHiLiminalPointLightStyle") == STYLE
            and info.get("ARCHiLiminalPointLightSHA256") == expected, "Player light capability does not match")
    embedded = player / "Contents/Resources/Data/StreamingAssets/LiminalV008/light-v12"
    require(validate_light(embedded, source, finish) == expected, "Player embeds another light recipe")
    return expected


def package_light(light, source, finish, native_resources, unity_streaming_assets):
    expected = validate_light(light, source, finish)
    targets = [Path(native_resources) / "LiminalV008/light-v12", Path(unity_streaming_assets) / "LiminalV008/light-v12"]
    for target in targets:
        require(target.parent.is_dir() and not target.parent.is_symlink(), "Base package must be staged first")
        require(validate_finish(target.parent / "finish-v11", target.parent) == read_json(Path(light) / "manifest.json")["finishManifestSHA256"],
                "Finish must be staged before light")
        if target.exists() or target.is_symlink():
            require(validate_light(target, target.parent, target.parent / "finish-v11") == expected, "Stage contains another light recipe")
    for target in targets:
        if not target.exists():
            shutil.copytree(light, target, symlinks=False)
        require(validate_light(target, target.parent, target.parent / "finish-v11") == expected, "Copied light bytes changed")
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    check = modes.add_parser("check-player")
    for name in ("light", "source", "finish", "player"):
        check.add_argument(name, type=Path)
    package = modes.add_parser("package")
    for name in ("light", "source", "finish", "native_resources", "unity_streaming_assets"):
        package.add_argument(name, type=Path)
    args = vars(parser.parse_args())
    mode = args.pop("mode")
    print(validate_player(**args) if mode == "check-player" else package_light(**args))


if __name__ == "__main__":
    main()
