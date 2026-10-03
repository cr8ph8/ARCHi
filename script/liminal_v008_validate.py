#!/usr/bin/env python3
"""Bounded, standard-library validation for the source-bound Liminal v008 asset."""
from __future__ import annotations

import argparse
import array
import hashlib
import heapq
import json
import math
import mmap
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zlib

HIP_SHA = "2a56c4faf40a8920109df44e8bc2dad599b2b45b67a26bf2bc4fd0c93dd60cc1"
NODE = "/obj/LIMINAL_POINTFORM/PARTICLE_CHOREOGRAPHY"
SCHEMA = "archi-liminal-point-asset/v2"
COUNT, RUNTIME_COUNT = 800000, 200000
MAX_PACKAGE, MAX_JSON = 1024**3, 1024**2
POSES = {"standing": 24, "curled": 66, "orb": 108}
SUBFRAMES = [base+offset for base in (24, 30, 36, 42, 48, 54, 59, 72, 78, 84, 90, 96, 102, 107)
             for offset in (.25, .5, .75)]
LIMITS = {"position": .01, "color": .01, "radius": .00001, "emission": .05}
CONTROL_VALUES = {"point_count": COUNT, "size_gain": .4, "glow_gain": 1,
                  "curl_frequency": 2.1, "release_stagger": .045, "lid_opening": 1.15,
                  "lid_definition": .8, "local_spin_turns": 1.15, "local_spin_radius": .065,
                  "micro_curl_amount": .01, "lion_initial_spin": 35, "lion_spin_max_offset": .3}
ENCODING = {"byteOrder": "little", "float": "ieee754-binary32", "masterStride": 100,
            "cohortStride": 8, "idStride": 4, "sampleStride": 32}
APPEARANCE = {"colorSpace": "linear-rec709", "radiusAttribute": "pscale",
              "emissionAttribute": "heat", "emissionRule": "Cd*heat"}
DEPENDENCIES = [
    ("geo/Meshy_AI_Emberstar_Cub_0927063736_texture_fbx/Meshy_AI_Emberstar_Cub_0927063736_texture.fbx", "0263627a4dd18aad08dfc76c58e254fc826920e8f31a80fb43cc4e394e8c9f8f", 44379948),
    ("geo/Meshy_AI_Emberstar_Cub_0927063736_texture_fbx/Meshy_AI_Emberstar_Cub_0927063736_texture.png", "cc7df38bcbee3e21f300afec68ba73d33a10ee36212a98de48bcac2d5b6a154e", 7310951),
    ("geo/Meshy_AI_Solar_Lion_s_Embrace_0927065508_texture_fbx/Meshy_AI_Solar_Lion_s_Embrace_0927065508_texture_fbx/Meshy_AI_Solar_Lion_s_Embrace_0927065508_texture.fbx", "57e90d05f64cad19370f651290090b5ab1c4fa73e97757fe78ac82d0d2eb9c2f", 35253484),
    ("geo/Meshy_AI_Solar_Lion_s_Embrace_0927065508_texture_fbx/Meshy_AI_Solar_Lion_s_Embrace_0927065508_texture_fbx/Meshy_AI_Solar_Lion_s_Embrace_0927065508_texture.png", "bae9ad29d0b46b772886e8890c9b242fb4bdaa1d96e338c175c97c70e48e2aa8", 6668658),
]
SAMPLE = struct.Struct("<8f")
MASTER = struct.Struct("<I24f")


class InvalidAsset(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidAsset(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected), f"{label}: unexpected fields")


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    require(path.stat().st_size <= MAX_JSON, f"JSON too large: {path.name}")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(InvalidAsset(f"nonfinite JSON: {value}")))


def safe_file(root, name):
    require(isinstance(name, str) and "\\" not in name, "invalid relative path")
    pure = PurePosixPath(name)
    require(not pure.is_absolute() and pure.parts and str(pure) == name
            and all(part not in ("..", ".", "") for part in pure.parts), "unsafe relative path")
    candidate = root
    for part in pure.parts:
        candidate = candidate / part
        require(not candidate.is_symlink(), f"symlink rejected: {name}")
    require(candidate.is_file(), f"file missing: {name}")
    return candidate


def file_ref(path, root):
    return {"file": path.relative_to(root).as_posix(), "sha256": sha256(path), "bytes": path.stat().st_size}


def ranked_ids(count=COUNT, runtime_count=RUNTIME_COUNT):
    require(0 < runtime_count <= count <= COUNT, "invalid ranking size")
    prefix = ("archi-liminal-lod/v1\n" + HIP_SHA + "\n").encode()
    ranked = heapq.nsmallest(runtime_count, ((hashlib.sha256(prefix + str(i).encode()).digest(), i)
                                           for i in range(count)))
    return array.array("I", (i for _, i in ranked))


def little_bytes(values):
    if sys.byteorder == "little":
        return values.tobytes()
    copy = array.array(values.typecode, values)
    copy.byteswap()
    return copy.tobytes()


def sample_rows(path):
    with path.open("rb") as stream:
        while chunk := stream.read(32 * 4096):
            require(len(chunk) % 32 == 0, "partial sample record")
            yield from SAMPLE.iter_unpack(chunk)


def include_row(bounds, row):
    require(len(row) == 8 and all(number(v) for v in row), "nonfinite sample")
    require(all(v >= 0 for v in row[3:]), "negative color/radius/emission")
    for k in range(3):
        bounds["min"][k] = min(bounds["min"][k], row[k])
        bounds["max"][k] = max(bounds["max"][k], row[k])
    bounds["maximumRadius"] = max(bounds["maximumRadius"], row[6])
    bounds["maximumEmission"] = max(bounds["maximumEmission"], row[7])


def empty_bounds():
    return {"min": [math.inf]*3, "max": [-math.inf]*3, "maximumRadius": 0., "maximumEmission": 0.}


def reference_camera(bounds):
    return {"projection": "orthographic", "center": [(a+b)*.5 for a, b in zip(bounds["min"], bounds["max"])],
            "span": max(b-a+2*bounds["maximumRadius"] for a, b in zip(bounds["min"], bounds["max"])) * 1.12,
            "direction": [0, 0, -1], "up": [0, 1, 0]}


def reference_png(rows, camera, size=512):
    """Scientific point projection, no scene/preview raster inputs or dependencies."""
    span = camera["span"]
    require(number(span) and span > 0 and size == 512, "invalid reference camera")
    pixels = array.array("f", [0.]) * (size*size*4)
    scale, center = size/span, camera["center"]
    for row in rows:
        x, y = (row[0]-center[0])*scale+(size-1)*.5, (size-1)*.5-(row[1]-center[1])*scale
        radius = max(.5, row[6]*scale)
        extent = math.ceil(radius*2)
        require(extent <= size, "reference radius exceeds viewport")
        for py in range(max(0, math.floor(y-extent)), min(size, math.ceil(y+extent)+1)):
            for px in range(max(0, math.floor(x-extent)), min(size, math.ceil(x+extent)+1)):
                distance = ((px-x)**2+(py-y)**2)/(radius*radius)
                if distance > 4:
                    continue
                weight = math.exp(-2*distance)
                index = (py*size+px)*4
                for k in range(3):
                    pixels[index+k] += row[k+3]*row[7]*weight
                pixels[index+3] += weight
    scanlines = bytearray()
    for y in range(size):
        scanlines.append(0)
        for x in range(size):
            i = (y*size+x)*4
            alpha = 1-math.exp(-pixels[i+3])
            for k in range(3):
                linear = min(1., (1-math.exp(-pixels[i+k]))/alpha) if alpha > 0 else 0.
                srgb = 12.92*linear if linear <= .0031308 else 1.055*linear**(1/2.4)-.055
                scanlines.append(round(255*srgb))
            scanlines.append(round(255*alpha))
    def chunk(tag, data):
        return struct.pack(">I", len(data))+tag+data+struct.pack(">I", zlib.crc32(tag+data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"sRGB", b"\0")
            + chunk(b"IDAT", zlib.compress(bytes(scanlines), 9)) + chunk(b"IEND", b""))


def reference_png_pixels(payload):
    """Decode only our bounded RGBA/no-filter PNG subset, independent of zlib version."""
    require(len(payload) <= 2*1024**2 and payload[:8] == b"\x89PNG\r\n\x1a\n", "invalid reference PNG")
    offset, chunks = 8, []
    while offset < len(payload):
        require(offset+12 <= len(payload), "truncated PNG chunk")
        size = struct.unpack_from(">I", payload, offset)[0]
        require(offset+12+size <= len(payload), "truncated PNG data")
        tag, data = payload[offset+4:offset+8], payload[offset+8:offset+8+size]
        crc = struct.unpack_from(">I", payload, offset+8+size)[0]
        require(zlib.crc32(tag+data) == crc, "invalid PNG CRC")
        chunks.append((tag, data))
        offset += 12+size
    require([tag for tag, _ in chunks] == [b"IHDR", b"sRGB", b"IDAT", b"IEND"], "unsupported reference PNG chunks")
    require(chunks[0][1] == struct.pack(">IIBBBBB", 512, 512, 8, 6, 0, 0, 0)
            and chunks[1][1] == b"\0" and chunks[-1][1] == b"", "unsupported reference PNG encoding")
    decoder = zlib.decompressobj()
    expected = 512*(512*4+1)
    raw = decoder.decompress(chunks[2][1], expected+1)
    require(len(raw) == expected and decoder.eof and not decoder.unconsumed_tail and not decoder.unused_data,
            "invalid or excessive reference PNG pixels")
    require(all(raw[y*(512*4+1)] == 0 for y in range(512)), "unsupported reference PNG row filter")
    return raw


def validate_comparison(receipt):
    keys(receipt, ("schema", "status", "hipSHA256", "node", "sourceCooked", "sampleFrames", "runtimePointCount",
                   "endpointFrames", "checks", "interpolation", "limits"), "comparison")
    require(receipt["schema"] == "archi-liminal-motion-comparison/v2" and receipt["status"] == "passed"
            and receipt["hipSHA256"] == HIP_SHA and receipt["node"] == NODE and receipt["sourceCooked"] is True,
            "source comparison unqualified")
    require(receipt["sampleFrames"] == list(range(1, 121)) and receipt["runtimePointCount"] == RUNTIME_COUNT
            and receipt["endpointFrames"] == list(POSES.values()), "incomplete source comparison")
    checks = receipt["checks"]
    keys(checks, ("identityError", "pathLimitError", "endpointPoseError", "poseAttributeError", "widthError", "idMismatchCount"), "checks")
    require(type(checks["idMismatchCount"]) is int and checks["idMismatchCount"] == 0, "ID mismatch")
    require(all(number(v) and 0 <= v <= .00001 for k, v in checks.items() if k != "idMismatchCount"), "source diagnostics exceed limits")
    interp = receipt["interpolation"]
    keys(interp, ("evaluated", "subframes", "comparedPointCount", *LIMITS), "interpolation")
    require(interp["evaluated"] is True and interp["subframes"] == SUBFRAMES
            and interp["comparedPointCount"] == RUNTIME_COUNT and receipt["limits"] == LIMITS, "interpolation unqualified")
    require(all(number(interp[k]) and 0 <= interp[k] <= limit for k, limit in LIMITS.items()), "interpolation exceeds limits")


def validate_package(directory):
    root = Path(directory).absolute()
    require(root.is_dir() and not root.is_symlink(), "package must be a regular directory")
    actual_files, total = set(), 0
    for path in root.rglob("*"):
        require(not path.is_symlink(), "package links rejected")
        if path.is_file():
            actual_files.add(path.relative_to(root).as_posix())
            total += path.stat().st_size
            require(total <= MAX_PACKAGE, "package exceeds 1 GiB")
    manifest = read_json(safe_file(root, "manifest.json"))
    keys(manifest, ("schema", "assetID", "source", "pointCount", "runtimePointCount", "encoding", "coordinates",
                    "appearance", "timeline", "bounds", "master", "cohorts", "lod", "frames", "motionControls",
                    "endpointImages", "comparison"), "manifest")
    require(manifest["schema"] == SCHEMA and manifest["assetID"] == "liminal-v008", "unsupported asset/version")
    require(manifest["pointCount"] == COUNT and manifest["runtimePointCount"] == RUNTIME_COUNT, "incorrect point counts")
    require(manifest["encoding"] == ENCODING and manifest["appearance"] == APPEARANCE, "unsupported encoding/appearance")
    source = manifest["source"]
    keys(source, ("hipSHA256", "houdiniVersion", "node", "originalUnchanged", "dependencies"), "source")
    require(source["hipSHA256"] == HIP_SHA and source["node"] == NODE and source["originalUnchanged"] is True,
            "unqualified authoring source (v008 required)")
    require(isinstance(source["houdiniVersion"], str) and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", source["houdiniVersion"]), "missing Houdini version")
    require(source["dependencies"] == [{"file": p, "sha256": h, "bytes": s} for p, h, s in DEPENDENCIES], "dependency mismatch")
    coords = manifest["coordinates"]
    keys(coords, ("space", "handedness", "upAxis", "units", "nativeMapping", "unityMapping", "objectToWorldRowMajor"), "coordinates")
    require({k: v for k, v in coords.items() if k != "objectToWorldRowMajor"} == {
        "space": "houdini-sop-local", "handedness": "right", "upAxis": "+Y", "units": "authored-scene-units",
        "nativeMapping": [1, 1, 1], "unityMapping": [1, 1, -1]}, "coordinate mismatch")
    require(isinstance(coords["objectToWorldRowMajor"], list) and len(coords["objectToWorldRowMajor"]) == 16
            and all(number(v) for v in coords["objectToWorldRowMajor"]), "invalid object transform")
    require(manifest["timeline"] == {"fps": 24, "firstFrame": 1, "lastFrame": 120, "interpolation": "nearest-half-up", "poseFrames": POSES}, "timeline mismatch")
    require(manifest["motionControls"] == CONTROL_VALUES, "motion controls mismatch")
    expected_files, checked = {"manifest.json"}, {}
    def check_ref(ref, size=None, name=None):
        keys(ref, ("file", "sha256", "bytes"), "file reference")
        require(type(ref["bytes"]) is int and 0 < ref["bytes"] <= MAX_PACKAGE, "invalid file length")
        require(isinstance(ref["sha256"], str) and re.fullmatch(r"[0-9a-f]{64}", ref["sha256"]), "invalid digest")
        require(size is None or ref["bytes"] == size, "incorrect declared binary length")
        require(name is None or ref["file"] == name, "unexpected file name")
        path = safe_file(root, ref["file"])
        require(path.stat().st_size == ref["bytes"], "file length mismatch")
        if ref["file"] in checked:
            require(checked[ref["file"]] == ref, "conflicting shared file reference")
        else:
            require(sha256(path) == ref["sha256"], f"digest mismatch: {ref['file']}")
            checked[ref["file"]] = ref
        expected_files.add(ref["file"])
        return path
    master = check_ref(manifest["master"], COUNT*100, "endpoints.bin")
    cohorts = check_ref(manifest["cohorts"], COUNT*8, "master-cohorts.bin")
    keys(manifest["lod"], ("algorithm", "counts", "ids"), "LOD")
    require(manifest["lod"]["algorithm"] == "sha256-rank-v1" and manifest["lod"]["counts"] == [50000, 100000, 200000], "LOD mismatch")
    ids_path = check_ref(manifest["lod"]["ids"], RUNTIME_COUNT*4, "lod-ids.bin")
    require(ids_path.read_bytes() == little_bytes(ranked_ids()), "LOD IDs/rank mismatch")
    ids = array.array("I"); ids.frombytes(ids_path.read_bytes())
    if sys.byteorder != "little": ids.byteswap()
    bounds = empty_bounds()
    with master.open("rb") as stream:
        index = 0
        while chunk := stream.read(100*4096):
            for record in MASTER.iter_unpack(chunk):
                require(record[0] == index, "master ID mismatch")
                for k in (1, 9, 17): include_row(bounds, record[k:k+8])
                index += 1
    with cohorts.open("rb") as stream:
        while chunk := stream.read(8*4096):
            require(all(a < 64 and b < 64 for a, b in struct.iter_unpack("<II", chunk)), "cohort out of range")
    require(isinstance(manifest["frames"], list) and len(manifest["frames"]) == 120, "incomplete sampled timeline")
    frame_paths, frame_refs, unique_samples = {}, {}, set()
    for expected, frame in enumerate(manifest["frames"], 1):
        keys(frame, ("frame", "file", "sha256", "bytes"), "frame")
        require(type(frame["frame"]) is int and frame["frame"] == expected, "incorrect frame ordering")
        require(isinstance(frame["file"], str) and re.fullmatch(r"frames/\d{4}\.bin", frame["file"]), "invalid sample filename")
        require(1 <= int(Path(frame["file"]).stem) <= expected, "sample points to a later frame")
        ref = {k: v for k, v in frame.items() if k != "frame"}
        path = check_ref(ref, RUNTIME_COUNT*32)
        frame_paths[expected], frame_refs[expected] = path, ref
        if path not in unique_samples:
            require(int(path.stem) == expected, "sample filename does not identify its first frame")
            for row in sample_rows(path): include_row(bounds, row)
            unique_samples.add(path)
    keys(manifest["bounds"], bounds, "bounds")
    require(manifest["bounds"] == bounds, "bounds differ from actual samples/master")
    with master.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        for pose_index, frame in enumerate(POSES.values()):
            raw = frame_paths[frame].read_bytes()
            require(all(raw[j*32:(j+1)*32] == data[i*100+4+pose_index*32:i*100+36+pose_index*32]
                        for j, i in enumerate(ids)), "endpoint LOD does not match master")
    comparison = check_ref(manifest["comparison"], name="comparison.json")
    validate_comparison(read_json(comparison))
    endpoints = manifest["endpointImages"]
    require(isinstance(endpoints, dict), "invalid endpoint images")
    if endpoints.get("status") == "unavailable":
        keys(endpoints, ("status", "camera", "images", "reason"), "endpoint images")
        require(endpoints["camera"] is None and endpoints["images"] == [] and isinstance(endpoints["reason"], str)
                and bool(endpoints["reason"]), "invalid unavailable endpoint images")
    else:
        keys(endpoints, ("status", "renderer", "camera", "images", "receipt"), "endpoint images")
        camera = reference_camera(bounds)
        require(endpoints["status"] == "qualified" and endpoints["renderer"] == "archi-point-reference/v1"
                and endpoints["camera"] == camera, "endpoint camera/renderer mismatch")
        require(isinstance(endpoints["images"], list) and len(endpoints["images"]) == 3, "missing endpoint images")
        bindings = []
        for image, (pose, frame) in zip(endpoints["images"], POSES.items()):
            keys(image, ("pose", "frame", "file", "sha256", "bytes"), "endpoint image")
            require(image["pose"] == pose and image["frame"] == frame, "endpoint pose mismatch")
            path = check_ref({k: image[k] for k in ("file", "sha256", "bytes")}, name=f"images/{pose}.png")
            require(path.stat().st_size <= 2*1024**2, "endpoint PNG too large")
            expected_png = reference_png(sample_rows(frame_paths[frame]), camera)
            require(reference_png_pixels(path.read_bytes()) == reference_png_pixels(expected_png), "endpoint pixels are not sampled v008 reference")
            bindings.append({**image, "sampleSHA256": frame_refs[frame]["sha256"]})
        receipt = read_json(check_ref(endpoints["receipt"], name="endpoint-images.json"))
        require(receipt == {"schema": "archi-liminal-endpoint-images/v1", "hipSHA256": HIP_SHA, "node": NODE,
                            "masterSHA256": manifest["master"]["sha256"], "renderer": endpoints["renderer"],
                            "camera": camera, "resolution": [512, 512], "transparent": True, "images": bindings}, "endpoint receipt mismatch")
    require(actual_files == expected_files, "unexpected files in runtime package")
    return {"status": "passed", "schema": SCHEMA, "manifestSHA256": sha256(root/"manifest.json"),
            "packageBytes": total, "pointCount": COUNT, "runtimePointCount": RUNTIME_COUNT,
            "uniqueSampleFiles": len(unique_samples), "endpointImageStatus": endpoints["status"],
            "qualification": "Format/source-receipt validation; runtime display and owner visual acceptance are separate."}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="newly exported LiminalV008 loose package")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(validate_package(args.package), indent=2))
    except (OSError, ValueError, KeyError, TypeError, struct.error) as error:
        print(f"Rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
