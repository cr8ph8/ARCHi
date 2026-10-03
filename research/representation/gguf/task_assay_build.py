#!/usr/bin/env python3
"""Compile only the scalar task protocol worker against the sealed text adapter.

No downloads, model calls, installation, or modification of the original runtime.
The copied mathematical dylibs must remain byte-identical to the qualified build.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BASE_MANIFEST = "861c945343c183d1df1e8ba27517d8eaa4d2d5d9b81cfc8e11d10f66a7981e9f"
BACKEND = "llama.cpp:161755f29+archi-qwen35-text-v1"
BLOB = "dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c"
READER = "b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    base, output = args.base_build.resolve(), args.output.resolve()
    if not output.is_relative_to(REPO / "output") or output.exists():
        raise ValueError("Choose a fresh checkout output directory")
    original = base / "runtime"
    manifest_path = original / "build-manifest.json"
    if digest(manifest_path) != BASE_MANIFEST:
        raise ValueError("Base runtime manifest differs from the qualified adapter")
    manifest = json.loads(manifest_path.read_bytes())
    for name, expected in manifest["runtime_sha256"].items():
        path = original / name
        if path.is_symlink() or not path.is_file() or digest(path) != expected:
            raise ValueError("Original runtime member changed: " + name)
    source = base / "source"
    for name, expected in manifest["compiled_source_file_sha256"].items():
        if digest(source / name) != expected:
            raise ValueError("Cached upstream header/source changed: " + name)
    output.mkdir(parents=True)
    runtime = output / "runtime"
    runtime.mkdir()
    for name in manifest["runtime_sha256"]:
        if name != "archi-gguf-shadow":
            shutil.copyfile(original / name, runtime / name)
    for name in ["OLLAMA_LICENSE", "text-compat-provenance.json"]:
        shutil.copyfile(HERE / name, runtime / name)
    frozen = output / "protocol-source"
    frozen.mkdir()
    for name in ["worker.cpp", "task_assay.h", "task_assay_build.py"]:
        shutil.copyfile(HERE / name, frozen / name)
    worker = runtime / "archi-gguf-shadow"
    command = ["xcrun", "clang++", "-std=c++17", "-O2", "-arch", "arm64", "-Wno-deprecated-declarations",
        '-DARCHI_GGUF_BACKEND="' + BACKEND + '"', '-DARCHI_QWEN35_BLOB="' + BLOB + '"',
        str(frozen / "worker.cpp"), "-I", str(source / "include"), "-I", str(source / "ggml/include"),
        "-I", str(source / "vendor/nlohmann"), "-Wl,-rpath,@loader_path",
        *[str(runtime / name) for name in ["libllama.0.dylib", "libggml.0.dylib", "libggml-base.0.dylib"]],
        "-o", str(worker)]
    (output / "compile-command.json").write_text(json.dumps(command, indent=2) + "\n")
    with (output / "compile.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(worker)],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    for name, expected in manifest["runtime_sha256"].items():
        if name.endswith(".dylib") and digest(runtime / name) != expected:
            raise ValueError("Mathematical library changed during worker build")
    manifest.update({
        "parent_runtime_manifest_sha256": BASE_MANIFEST,
        "worker_source_sha256": digest(frozen / "worker.cpp"),
        "task_assay_header_sha256": digest(frozen / "task_assay.h"),
        "task_assay_recipe_sha256": digest(frozen / "task_assay_build.py"),
        "native_protocols": ["archi-gguf-shadow-request/v1", "archi-record-measurement-request/v1"],
        "record_measurement": {
            "protocol": "archi-record-measurement/v1", "arguments": ["--measure-record", "--validate-record"],
            "reader_artifact_sha256": READER,
            "numeric_sha256": "3cd3b593f393d252eef9d63f8090a685a52e0ce3c37f94f778ad0ccea0515bef",
            "layer": "l_out-31", "token_rule": "prompt-last",
            "measurement_scope": "synthetic-record-field-support/prompt-final/ridge-v1",
            "max_input_tokens": 512, "max_new_tokens": 0, "deadline_ms": 180000,
            "response": "scalars-only", "synthetic_only_required": False,
        },
        "mathematical_libraries_unchanged": True,
        "model_loaded": False, "inference_executed": False,
        "runtime_sha256": {p.name: digest(p) for p in sorted(runtime.iterdir()) if p.is_file()},
    })
    (runtime / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"runtime": str(runtime), "manifestSHA256": digest(runtime / "build-manifest.json"),
                      "workerSHA256": digest(worker), "mathematicalLibrariesUnchanged": True,
                      "modelLoaded": False, "inferenceExecuted": False}))


if __name__ == "__main__":
    main()
