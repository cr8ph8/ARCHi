#!/usr/bin/env python3
"""Cook the pinned v008 HIP copy with hython and export an immutable point package.

No scene saves, ROP execution, source edits, external modules or network requests.
Both this file and liminal_v008_validate.py must be placed in the same directory.
"""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import shutil
import struct
import sys

import liminal_v008_validate as contract

VEX_SHA = "9c7bd9b7d6247b78c05cad35d3cd3728f2f9e43f03cff46c0744a8c74b5f957a"
INPUTS = ["/obj/LIMINAL_POINTFORM/ASSIGN_LION_COLOR_COHORT",
          "/obj/LIMINAL_POINTFORM/CURLED_POSE_BY_PTNUM",
          "/obj/LIMINAL_POINTFORM/ADVECT_LION_COLOR_GUIDES",
          "/obj/LIMINAL_POINTFORM/CURL_GUIDE_MOTION"]
CONTROL_NODE = "/obj/LIMINAL_CONTROLS"
POSE_ATTRIBUTES = ("sourceP", "curlP", "targetP")
CONTROL_EXPRESSIONS = {"lion_to_curl": "smooth($F,24,60)", "curl_to_orb": "smooth($F,72,108)"}


def write_bytes(path, data):
    with path.open("xb") as stream:
        stream.write(data)


def write_json(path, value):
    payload = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False)+"\n").encode()
    contract.require(len(payload) <= contract.MAX_JSON, "receipt too large")
    write_bytes(path, payload)


def check_source(source):
    contract.require(source.name == "Liminal-v008-lion-spin-blend.hiplc", "only the pinned v008 HIP is accepted")
    contract.require(source.is_file() and not source.is_symlink(), "source HIP missing or linked")
    contract.require(contract.sha256(source) == contract.HIP_SHA, "v008 HIP SHA256 mismatch; v002 and modified scenes rejected")
    root = source.parent.parent
    for name, digest, size in contract.DEPENDENCIES:
        path = contract.safe_file(root, name)
        contract.require(path.stat().st_size == size and contract.sha256(path) == digest,
                         f"required authoring dependency mismatch: {name}")
    return root


def prepare_copy(source, output, work):
    source_root = check_source(source)
    for target in (output, work):
        contract.require(not target.exists() and not target.is_symlink(), f"refusing overwrite: {target}")
        contract.require(source_root != target and source_root not in target.parents,
                         "output/work directory must be outside preserved Liminal source")
    contract.require(output != work and output not in work.parents and work not in output.parents,
                     "output and working directories must be separate")
    # Resolve parents before any writes, preventing a symlinked parent from redirecting into source.
    for target in (output, work):
        resolved = target.resolve()
        contract.require(source_root.resolve() != resolved and source_root.resolve() not in resolved.parents,
                         "resolved output/work path would modify preserved source")
    output.mkdir(parents=True)
    work.mkdir(parents=True)
    (work/"hip").mkdir()
    copy = work/"hip"/source.name
    shutil.copyfile(source, copy)
    for name, _, _ in contract.DEPENDENCIES:
        target = work/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_root/name, target)
    check_source(copy)
    return copy


def bulk(geo, name, size, kind, hou):
    attribute = geo.findPointAttrib(name)
    contract.require(attribute is not None and attribute.size() == size,
                     f"missing or incorrect point attribute: {name}")
    expected = hou.attribData.Int if kind == "i" else hou.attribData.Float
    contract.require(attribute.dataType() == expected, f"incorrect attribute type: {name}")
    payload = (geo.pointIntAttribValuesAsString(name, hou.numericData.Int32) if kind == "i"
               else geo.pointFloatAttribValuesAsString(name, hou.numericData.Float32))
    values = array.array(kind)
    contract.require(values.itemsize == 4 and len(payload) == contract.COUNT*size*4,
                     f"incorrect attribute length: {name}")
    # HOM's native-endian binary buffer is converted to little endian only on file writes.
    values.frombytes(payload)
    return values


def vector_error(first, second):
    contract.require(len(first) == len(second) and len(first) % 3 == 0, "pose attribute size mismatch")
    if first == second:
        return 0.
    maximum = 0.
    for i in range(0, len(first), 3):
        values = (*first[i:i+3], *second[i:i+3])
        contract.require(all(contract.number(v) for v in values), "nonfinite pose attribute")
        maximum = max(maximum, math.sqrt(sum((first[i+k]-second[i+k])**2 for k in range(3))))
    return maximum


def pack_rows(attributes, ids):
    positions, colors, radii, emissions = (attributes[k] for k in ("P", "Cd", "pscale", "heat"))
    result = bytearray(len(ids)*32)
    for j, i in enumerate(ids):
        p = i*3
        contract.SAMPLE.pack_into(result, j*32, positions[p], positions[p+1], positions[p+2],
                                  colors[p], colors[p+1], colors[p+2], radii[i], emissions[i])
    return result


def comparison_errors(actual, before, after, fraction):
    contract.require(contract.number(fraction) and 0 <= fraction <= 1, "invalid sample fraction")
    contract.require(len(actual) == len(before) == len(after) and len(actual) % 32 == 0,
                     "comparison sample length mismatch")
    errors = {key: 0. for key in contract.LIMITS}
    for real, start, end in zip(contract.SAMPLE.iter_unpack(actual), contract.SAMPLE.iter_unpack(before),
                                contract.SAMPLE.iter_unpack(after)):
        contract.require(all(contract.number(v) for v in (*real, *start, *end)), "nonfinite interpolation sample")
        # v008's $F controls hold rounded integer frames. Linear interpolation
        # creates states that the unchanged source does not produce.
        expected = start if fraction < .5 else end
        delta = [abs(real[k]-expected[k]) for k in range(8)]
        errors["position"] = max(errors["position"], math.sqrt(sum(v*v for v in delta[:3])))
        errors["color"] = max(errors["color"], *delta[3:6])
        errors["radius"] = max(errors["radius"], delta[6])
        errors["emission"] = max(errors["emission"], delta[7])
    return errors


class SourceCook:
    def __init__(self, hou):
        self.hou = hou
        self.node = hou.node(contract.NODE)
        self.controls = hou.node(CONTROL_NODE)
        contract.require(self.node is not None and self.controls is not None, "required authoring nodes missing")
        contract.require(self.node.type().name().split(":")[0] == "attribwrangle", "choreography is not the inspected wrangle")
        contract.require([node.path() if node else None for node in self.node.inputs()] == INPUTS,
                         "choreography inputs differ from inspected v008")
        snippet = self.node.parm("snippet")
        contract.require(snippet is not None and hashlib.sha256(snippet.evalAsString().replace("\r\n", "\n").strip().encode()).hexdigest() == VEX_SHA,
                         "v008 choreography VEX differs from inspected source")
        for node_path, input_path in ((INPUTS[1], "/obj/CURLED_LION_SOURCE/OUT_CURLED_TARGETS"),
                                      (INPUTS[3], "/obj/CURLED_LION_SOURCE/ADVECT_CURL_COLOR_GUIDES")):
            node = hou.node(node_path)
            contract.require(node.parm("objpath1") is not None and node.parm("objpath1").evalAsString() == input_path,
                             "curled source merge path mismatch")
            contract.require(node.parm("xformtype") is not None and node.parm("xformtype").evalAsString() == "none",
                             "curled source merge transforms unexpectedly")
        for name in (*contract.CONTROL_VALUES, "lion_to_curl", "curl_to_orb"):
            contract.require(self.controls.parm(name) is not None, f"required motion parameter missing: {name}")
        for name, expression in CONTROL_EXPRESSIONS.items():
            contract.require(self.controls.parm(name).expressionLanguage() == hou.exprLanguage.Hscript
                             and self.controls.parm(name).expression() == expression,
                             f"source frame expression changed: {name}")
        for node_path in ("/obj/LIMINAL_POINTFORM/LION_COLOR_CENTERS", "/obj/CURLED_LION_SOURCE/CURL_COLOR_CENTERS"):
            node = hou.node(node_path)
            contract.require(node is not None and node.parm("num_clusters") is not None
                             and node.parm("num_clusters").evalAsInt() == 64, "source requires 64 motion cohorts")
        contract.require(hou.fps() == 24, "source FPS differs from 24")
        self.pose_vectors = None
        self.cohort_bytes = None
        self.transform = None
        self.checks = {"identityError": 0., "pathLimitError": 0., "endpointPoseError": 0.,
                       "poseAttributeError": 0., "widthError": 0., "idMismatchCount": 0}
        self.frames_cooked = []

    def cook(self, frame):
        hou = self.hou
        hou.setFrame(frame)
        for key, value in contract.CONTROL_VALUES.items():
            actual = self.controls.parm(key).eval()
            contract.require(contract.number(actual) and abs(actual-value) < 1e-8,
                             f"motion parameter changed at frame {frame}: {key}")
        a, b = (self.controls.parm(key).eval() for key in ("lion_to_curl", "curl_to_orb"))
        contract.require(all(contract.number(v) and 0 <= v <= 1 for v in (a, b)), "invalid source blend controls")
        expected = {24: (0, 0), 66: (1, 0), 108: (1, 1)}.get(frame)
        contract.require(expected is None or (a, b) == expected, f"endpoint controls do not identify pose at frame {frame}")
        transform = list(self.node.parent().worldTransform().asTuple())
        contract.require(len(transform) == 16 and all(contract.number(v) for v in transform), "invalid source object transform")
        if self.transform is None:
            self.transform = transform
        contract.require(transform == self.transform, "animated object transform unsupported; cannot drop motion")
        geo = self.node.geometryAtFrame(frame)
        contract.require(not self.node.errors() and not self.node.warnings(),
                         f"source cook diagnostics at {frame}: {self.node.errors()} {self.node.warnings()}")
        curled = self.node.inputs()[1].geometryAtFrame(frame)
        contract.require(geo.intrinsicValue("pointcount") == contract.COUNT
                         and curled.intrinsicValue("pointcount") == contract.COUNT, "full 800000 source/curled points required")
        ids, curled_ids = bulk(geo, "id", 1, "i", hou), bulk(curled, "id", 1, "i", hou)
        mismatch = sum(i != identity or i != curled_ids[i] for i, identity in enumerate(ids))
        self.checks["idMismatchCount"] += mismatch
        contract.require(mismatch == 0, "source/curled immutable ID order mismatch")
        cohorts = (bulk(geo, "motion_cluster", 1, "i", hou), bulk(curled, "motion_cluster", 1, "i", hou))
        contract.require(all(0 <= value < 64 for values in cohorts for value in values), "invalid motion cohort")
        cohort_bytes = tuple(values.tobytes() for values in cohorts)
        if self.cohort_bytes is None:
            self.cohort_bytes = cohort_bytes
        contract.require(cohort_bytes == self.cohort_bytes, "motion cohort assignment changes across frames")
        attributes = {name: bulk(geo, name, size, "f", hou) for name, size in
                      (("P", 3), ("Cd", 3), ("pscale", 1), ("heat", 1))}
        for name, values in attributes.items():
            contract.require(all(math.isfinite(v) and (name == "P" or v >= 0) for v in values),
                             f"invalid finite/nonnegative sample field: {name}")
        for name, key, kind in (("identity_error", "identityError", "i"),
                                 ("path_limit_error", "pathLimitError", "f"), ("pose_error", "endpointPoseError", "f")):
            values = bulk(geo, name, 1, kind, hou)
            contract.require(all(math.isfinite(v) and v >= 0 for v in values), f"invalid diagnostic: {name}")
            self.checks[key] = max(self.checks[key], max(values))
        widths = bulk(geo, "width", 1, "f", hou)
        contract.require(all(math.isfinite(v) and v >= 0 for v in widths), "invalid width")
        self.checks["widthError"] = max(self.checks["widthError"], max(abs(w-2*r) for w, r in zip(widths, attributes["pscale"])))
        poses = [bulk(geo, name, 3, "f", hou) for name in POSE_ATTRIBUTES]
        contract.require(all(math.isfinite(v) for values in poses for v in values), "nonfinite retained source/target pose")
        if self.pose_vectors is None:
            self.pose_vectors = poses
        for actual, baseline in zip(poses, self.pose_vectors):
            self.checks["poseAttributeError"] = max(self.checks["poseAttributeError"], vector_error(actual, baseline))
        if frame in contract.POSES.values():
            index = list(contract.POSES.values()).index(frame)
            self.checks["poseAttributeError"] = max(self.checks["poseAttributeError"], vector_error(attributes["P"], self.pose_vectors[index]))
        contract.require(all(value <= .00001 for key, value in self.checks.items() if key != "idMismatchCount"),
                         "source diagnostics/pose/width exceed contract; see failure receipt")
        self.frames_cooked.append(frame)
        return attributes


def write_master(work, output, bounds):
    streams = [(work/f"pose-{pose}.bin").open("rb") for pose in contract.POSES]
    try:
        with (output/"endpoints.bin").open("xb") as destination:
            for start in range(0, contract.COUNT, 4096):
                count = min(4096, contract.COUNT-start)
                chunks = [stream.read(count*32) for stream in streams]
                contract.require(all(len(chunk) == count*32 for chunk in chunks), "short endpoint scratch file")
                packed = bytearray(count*100)
                for j in range(count):
                    offset = j*100
                    struct.pack_into("<I", packed, offset, start+j)
                    for k, chunk in enumerate(chunks):
                        row = chunk[j*32:(j+1)*32]
                        packed[offset+4+k*32:offset+36+k*32] = row
                        contract.include_row(bounds, contract.SAMPLE.unpack(row))
                destination.write(packed)
    finally:
        for stream in streams: stream.close()


def write_cohorts(source, output):
    arrays = []
    for raw in source.cohort_bytes:
        values = array.array("i"); values.frombytes(raw); arrays.append(values)
    with (output/"master-cohorts.bin").open("xb") as stream:
        for start in range(0, contract.COUNT, 4096):
            count = min(4096, contract.COUNT-start)
            packed = bytearray(count*8)
            for j in range(count):
                struct.pack_into("<II", packed, j*8, arrays[0][start+j], arrays[1][start+j])
            stream.write(packed)


def endpoint_images(output, bounds, frames, master):
    camera = contract.reference_camera(bounds)
    renderer = "archi-point-reference/v1"
    (output/"images").mkdir()
    images, bindings = [], []
    for pose, frame in contract.POSES.items():
        sample = frames[frame-1]
        png = contract.reference_png(contract.sample_rows(output/sample["file"]), camera)
        path = output/"images"/f"{pose}.png"
        write_bytes(path, png)
        image = {"pose": pose, "frame": frame, **contract.file_ref(path, output)}
        images.append(image)
        bindings.append({**image, "sampleSHA256": sample["sha256"]})
    receipt = {"schema": "archi-liminal-endpoint-images/v1", "hipSHA256": contract.HIP_SHA, "node": contract.NODE,
               "masterSHA256": master["sha256"], "renderer": renderer, "camera": camera,
               "resolution": [512, 512], "transparent": True, "images": bindings}
    write_json(output/"endpoint-images.json", receipt)
    return {"status": "qualified", "renderer": renderer, "camera": camera, "images": images,
            "receipt": contract.file_ref(output/"endpoint-images.json", output)}


def export(args):
    try:
        import hou
    except ImportError as error:
        raise contract.InvalidAsset("Houdini hou module unavailable; run this script with installed hython. No source cook was performed.") from error
    # This pinned .hiplc workflow must not silently fall back to Apprentice or
    # another license mode. HOM reports the category, not the checked-out SKU.
    def require_indie(stage):
        category = hou.licenseCategory()
        contract.require(category == hou.licenseCategoryType.Indie,
                         f"Indie license category required at {stage}: {category}")
        return {"stage": stage, "category": "Indie"}

    license_checks = [require_indie("before-source-copy")]
    source_path, output, work = args.source.resolve(), args.output.absolute(), args.work_directory.absolute()
    copy = prepare_copy(source_path, output, work)
    source = None
    try:
        hou.hipFile.load(str(copy), suppress_save_prompt=True, ignore_load_warnings=False)
        license_checks.append(require_indie("after-source-load"))
        source = SourceCook(hou)
        ids = contract.ranked_ids()
        write_bytes(output/"lod-ids.bin", contract.little_bytes(ids))
        bounds = contract.empty_bounds()
        for pose, frame in contract.POSES.items():
            print(f"Cooking full master: {pose} frame {frame}", flush=True)
            attributes = source.cook(frame)
            write_bytes(work/f"pose-{pose}.bin", pack_rows(attributes, range(contract.COUNT)))
            del attributes
        write_master(work, output, bounds)
        write_cohorts(source, output)
        (output/"frames").mkdir()
        frames, dedup = [], {}
        for frame in range(1, 121):
            print(f"Cooking sampled motion: {frame}/120", flush=True)
            attributes = source.cook(frame)
            raw = pack_rows(attributes, ids)
            del attributes
            digest = hashlib.sha256(raw).hexdigest()
            if digest in dedup:
                ref = dedup[digest]
                contract.require((output/ref["file"]).read_bytes() == raw, "sample digest collision")
            else:
                path = output/"frames"/f"{frame:04d}.bin"
                write_bytes(path, raw)
                ref = contract.file_ref(path, output)
                dedup[digest] = ref
                for row in contract.SAMPLE.iter_unpack(raw): contract.include_row(bounds, row)
            frames.append({"frame": frame, **ref})
        errors = {key: 0. for key in contract.LIMITS}
        frame_errors = []
        for frame in contract.SUBFRAMES:
            print(f"Comparing actual Houdini subframe: {frame}", flush=True)
            attributes = source.cook(frame)
            real = pack_rows(attributes, ids)
            del attributes
            lower = math.floor(frame)
            measured = comparison_errors(real, (output/frames[lower-1]["file"]).read_bytes(),
                                          (output/frames[lower]["file"]).read_bytes(), frame-lower)
            frame_errors.append({"frame": frame, "errors": measured})
            for key in errors: errors[key] = max(errors[key], measured[key])
        # Retain authoring diagnostics separately; they do not relax the shared
        # runtime receipt or qualify a failed motion comparison.
        write_json(work/"motion-diagnostics.json", {"sampleFrames": frames, "comparisons": frame_errors,
                   "licenseCategoryChecks": license_checks, "limits": contract.LIMITS})
        receipt = {"schema": "archi-liminal-motion-comparison/v2", "status": "passed", "hipSHA256": contract.HIP_SHA,
                   "node": contract.NODE, "sourceCooked": True, "sampleFrames": list(range(1, 121)),
                   "runtimePointCount": contract.RUNTIME_COUNT, "endpointFrames": list(contract.POSES.values()),
                   "checks": source.checks, "interpolation": {"evaluated": True, "subframes": contract.SUBFRAMES,
                   "comparedPointCount": contract.RUNTIME_COUNT, **errors}, "limits": contract.LIMITS}
        # Keep exact failed comparison in authoring work; never call a failed receipt passed in the package.
        try:
            contract.validate_comparison(receipt)
        except contract.InvalidAsset:
            receipt["status"] = "failed"
            write_json(work/"comparison-failed.json", receipt)
            raise
        write_json(output/"comparison.json", receipt)
        master = contract.file_ref(output/"endpoints.bin", output)
        images = (endpoint_images(output, bounds, frames, master) if args.render_endpoints else
                  {"status": "unavailable", "camera": None, "images": [],
                   "reason": "No camera-qualified transparent endpoint renders were produced."})
        check_source(source_path)
        check_source(copy)
        manifest = {"schema": contract.SCHEMA, "assetID": "liminal-v008", "source": {
            "hipSHA256": contract.HIP_SHA, "houdiniVersion": hou.applicationVersionString(), "node": contract.NODE,
            "originalUnchanged": True, "dependencies": [{"file": p, "sha256": h, "bytes": n} for p, h, n in contract.DEPENDENCIES]},
            "pointCount": contract.COUNT, "runtimePointCount": contract.RUNTIME_COUNT, "encoding": contract.ENCODING,
            "coordinates": {"space": "houdini-sop-local", "handedness": "right", "upAxis": "+Y", "units": "authored-scene-units",
                            "nativeMapping": [1, 1, 1], "unityMapping": [1, 1, -1], "objectToWorldRowMajor": source.transform},
            "appearance": contract.APPEARANCE, "timeline": {"fps": 24, "firstFrame": 1, "lastFrame": 120,
                                                           "interpolation": "nearest-half-up", "poseFrames": contract.POSES},
            "bounds": bounds, "master": master, "cohorts": contract.file_ref(output/"master-cohorts.bin", output),
            "lod": {"algorithm": "sha256-rank-v1", "counts": [50000, 100000, 200000],
                    "ids": contract.file_ref(output/"lod-ids.bin", output)}, "frames": frames,
            "motionControls": contract.CONTROL_VALUES, "endpointImages": images,
            "comparison": contract.file_ref(output/"comparison.json", output)}
        write_json(output/"manifest.json", manifest)
        result = contract.validate_package(output)
        license_checks.append(require_indie("before-export-receipt"))
        write_json(work/"export-receipt.json", {**result, "sourceCooked": True, "originalUnchanged": True,
                                               "licenseCategoryChecks": license_checks,
                                               "runtimeDisplayQualified": False, "ownerVisualAcceptance": False})
        return result
    except Exception as error:
        # This directory was exclusively created above. Revoke only our newly written manifest.
        if (output/"manifest.json").exists():
            (output/"manifest.json").unlink()
        failure = {"schema": "archi-liminal-export-failure/v1", "status": "failed", "error": str(error),
                   "hipSHA256": contract.HIP_SHA, "node": contract.NODE, "qualifiedManifest": False,
                   "framesCooked": source.frames_cooked if source else [], "checks": source.checks if source else {},
                   "licenseCategoryChecks": license_checks}
        write_json(work/"export-failure.json", failure)
        raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="pinned v008 authoring HIP, read-only")
    parser.add_argument("--output", required=True, type=Path, help="new loose runtime package directory (must not exist)")
    parser.add_argument("--work-directory", required=True, type=Path, help="separate new source-copy/scratch/receipt directory")
    parser.add_argument("--render-endpoints", action="store_true", help="produce actual-data transparent 512-square CPU point-reference PNGs; no Karma/ROP render")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(export(args), indent=2))
    except Exception as error:
        print(f"Export rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
