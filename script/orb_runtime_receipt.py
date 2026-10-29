#!/usr/bin/env python3
"""Verify completed orb evidence against its source and captures; never run Unity.

This checks consistency and integrity, not independent attestation that Unity ran.
Review the Editor log and actual images before accepting rendering quality.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import struct


SCHEMA = "archi-orb-room-runtime-acceptance/v1"
UNITY_VERSION = "6000.5.4f1"
SOURCE_PATHS = {
    "SOURCE_SHA256SUMS", "unity/ARCHi/ProjectSettings/ProjectVersion.txt",
    "unity/ARCHi/ProjectSettings/GraphicsSettings.asset", "unity/ARCHi/ProjectSettings/QualitySettings.asset",
    "unity/ARCHi/Assets/ARCHi/Editor/OrbRoomRuntimeValidation.cs",
    *["unity/ARCHi/Assets/ARCHi/Runtime/" + name + ".cs" for name in
      ("OrbRoomStage", "OrbRoomNavigation", "OrbBody", "OrbParticleBody", "OrbRoomTheme", "OrbPresentation", "ArenaBloom")],
    "unity/ARCHi/Assets/Resources/KIN/ArenaBloom.shader",
    *["unity/ARCHi/Assets/ARCHi/Resources/Orb/" + name + ".shader" for name in
      ("OrbEnergy", "OrbParticles", "OrbRoomSurface")],
}
CAPTURE_PATHS = {
    "idle.png", "idle-particles-hidden.png", "lamp-attention-hidden.png",
    "paused.png", "paused-after-ticks.png", "exploration-complete.png",
    *[name + suffix for name in ("desk", "shelf", "lamp", "window") for suffix in (".png", "-particles-hidden.png")],
}
REQUIRED_ASSERTIONS = {
    "entry.pinned-unity-version", "entry.real-graphics-device",
    "scene.empty-source-scenes-never-enter-play-mode", "render.real-graphics-device-in-play-mode",
    "room.ready-with-four-registered-objects", "particles.real-mesh-has-720-quads", "particles.real-gpu-contribution",
    "render.lamp.attention-contributes-near-target-outside-orb-body", "pause.actual-render-pixels-held",
    "tour.visits-each-object-once-and-returns-home", "picking.projected-lamp-through-letterboxed-viewport",
    "retirement.disabled-target-clears-contour-and-rejects-old-reference",
    "session.replacement-clears-route-highlight-and-old-reference", "stop.native-stop-clears-contour",
    "suspend.hides-interaction-and-clears-motion", "navigation.observed-centers-clear-actual-room-surfaces",
    "lifecycle.no-fixture-gameobjects-left",
    *["lifecycle." + name + ".deferred-destruction-releases-owned-resources" for name in ("first", "reopen-0", "reopen-1")],
    *[prefix + name + suffix for name in ("desk", "shelf", "lamp", "window") for prefix, suffix in
      (("selection.", ".accepted-and-bound"), ("navigation.", ".reaches-approach"), ("render.", ".visible-particles"))],
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def regular_file(root, name):
    path = root / name
    require(path.is_file() and path.resolve() == path, "Missing file or symbolic link: " + name)
    return path


def inventory(rows, expected, label):
    require(isinstance(rows, list), label + " inventory is missing")
    result = {}
    for row in rows:
        require(isinstance(row, dict), label + " entry must be an object")
        name = row.get("path" if label == "Source" else "file")
        require(isinstance(name, str) and name in expected and name not in result,
                label + " path is unexpected or duplicated")
        require(isinstance(row.get("sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
                label + " SHA-256 is invalid")
        result[name] = row
    require(set(result) == expected, label + " inventory is incomplete")
    return result


def verify(repo, output):
    repo, output = Path(repo).resolve(), Path(output).resolve()
    receipt = json.loads(regular_file(output, "acceptance.json").read_text())
    require(isinstance(receipt, dict), "Receipt must be an object")
    require(receipt.get("schema") == SCHEMA and receipt.get("passed") is True
            and type(receipt.get("failedAssertions")) is int and receipt["failedAssertions"] == 0
            and type(receipt.get("passedAssertions")) is int and receipt["passedAssertions"] > 0
            and receipt.get("errors") == [], "Orb runtime acceptance did not pass")
    require(receipt.get("unityVersion") == UNITY_VERSION, "Receipt has the wrong Unity version")
    require(isinstance(receipt.get("graphicsAPI"), str) and receipt["graphicsAPI"].strip()
            and receipt["graphicsAPI"].strip().lower() != "null"
            and isinstance(receipt.get("graphicsDevice"), str) and receipt["graphicsDevice"].strip(),
            "Receipt does not identify a graphics device")
    require(receipt.get("outputDirectory") == str(output), "Receipt belongs to another evidence directory")
    require(all(type(receipt.get(key)) is int and receipt[key] > 0 for key in ("ticks", "renderedPlayerFrames")),
            "Receipt has no simulated ticks or rendered player frames")
    clearance = receipt.get("minimumSampledClearance")
    require(type(clearance) in (int, float) and math.isfinite(clearance) and .6379 <= clearance < 100,
            "Receipt has no valid observed clearance")
    assertions = receipt.get("assertions")
    require(isinstance(assertions, list) and len(assertions) == receipt["passedAssertions"], "Assertion count is inconsistent")
    names = set()
    for assertion in assertions:
        require(isinstance(assertion, dict) and isinstance(assertion.get("name"), str)
                and assertion["name"] and assertion["name"] not in names and assertion.get("passed") is True,
                "Assertion is failed, malformed or duplicated")
        names.add(assertion["name"])
    require(REQUIRED_ASSERTIONS <= names, "Required runtime assertions are missing")
    sources = inventory(receipt.get("sources"), SOURCE_PATHS, "Source")
    captures = inventory(receipt.get("captures"), CAPTURE_PATHS, "Capture")
    for name, row in sources.items():
        require(hashlib.sha256(regular_file(repo, name).read_bytes()).hexdigest() == row["sha256"],
                "Source hash mismatch: " + name)
    for name, row in captures.items():
        data = regular_file(output, name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == row["sha256"], "Capture hash mismatch: " + name)
        require(len(data) > 33 and data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR"
                and struct.unpack(">II", data[16:24]) == (960, 720), "Capture is not a 960x720 PNG: " + name)
        if name.endswith("-particles-hidden.png") or name == "lamp-attention-hidden.png":
            threshold = 12 if name == "lamp-attention-hidden.png" else 24
            require(type(row.get("changedPixels")) is int and threshold < row["changedPixels"] <= 960 * 720,
                    "Capture has no qualifying particle difference: " + name)
    log = regular_file(output.parent, output.name + ".editor.log").read_text(errors="replace")
    require("ARCHI_ORB_RUNTIME_PASS " + str(output) in log, "Editor completion marker is missing")
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        verify(args.repo, args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, "Orb evidence verification failed: " + str(error) + "\n")
    print("Orb runtime evidence verified: " + str(args.output.resolve() / "acceptance.json"))
    print("Review the PNG captures and Editor log. Native input, installed-player behavior and device performance remain separate checks.")


if __name__ == "__main__":
    main()
