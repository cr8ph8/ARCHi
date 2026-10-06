#!/usr/bin/env python3
"""Copy the pinned, locally built shadow runtime without downloading anything."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


def validate_text_adapter(info):
    patch = info.get("compatibility_patch", {})
    expected = {
        "id": "archi-qwen35-text-v1", "backend_revision": "llama.cpp:161755f29+archi-qwen35-text-v1",
        "target": "src/llama-model-loader.cpp",
        "upstream_sha256": "efdb5f273bd1ab77301f2cadea1a5a804bafb28040aca033e45605a97a450242",
        "patched_sha256": "41b4e316bc4e79bf03830f9c2ec56d68d1666177cc7d338d447c9686e70547b9",
        "header_sha256": "d265ee679b9bf2beb2e5c850959ee4c3f0cd802602584331e64ca0c947069968",
        "recipe_sha256": "2616cabb6e545a70263692394b4f3a7292a8a2b9d5ab416b938bce1dda7f9209",
        "model_blob_sha256": "dec52a44569a2a25341c4e4d3fee25846eed4f6f0b936278e3a3c900bb99d37c",
        "model_bytes_modified": False, "base_text_tensor_count": 427, "alias_count": 24,
        "excluded_auxiliary_tensors": {"vision": 441, "mtp": 15},
        "official_ollama_revision": "b2da9e468af2479058ae18c6d908ed29de410684",
    }
    record = info.get("record_measurement", {})
    if (patch != expected
            or info.get("parent_runtime_manifest_sha256") != "861c945343c183d1df1e8ba27517d8eaa4d2d5d9b81cfc8e11d10f66a7981e9f"
            or info.get("mathematical_libraries_unchanged") is not True
            or info.get("native_protocols") != ["archi-gguf-shadow-request/v1", "archi-record-measurement-request/v1"]
            or record != {
                "protocol": "archi-record-measurement/v1", "arguments": ["--measure-record", "--validate-record"],
                "reader_artifact_sha256": "b699deda8bc7bdd99b5e362c88d16accdd66c163222e89647086b44a680a7ac0",
                "numeric_sha256": "3cd3b593f393d252eef9d63f8090a685a52e0ce3c37f94f778ad0ccea0515bef",
                "layer": "l_out-31", "token_rule": "prompt-last",
                "measurement_scope": "synthetic-record-field-support/prompt-final/ridge-v1",
                "max_input_tokens": 512, "max_new_tokens": 0, "deadline_ms": 180000,
                "response": "scalars-only", "synthetic_only_required": False,
            }
            or any(not re.fullmatch(r"[0-9a-f]{64}", info.get(key, "")) for key in
                   ["worker_source_sha256", "task_assay_header_sha256", "task_assay_recipe_sha256"])):
        raise ValueError("Unqualified task protocol or text adapter identity")
    pinned_members = {
        "libggml-base.0.dylib": "f6ff0dfea0691dd5bce7588d87e109fbbac67e4c5c566f2df107072287f9c24c",
        "libggml-cpu.0.dylib": "5d461f77c3296d571be0184811b754c6149cf9a1846c40361b3221265639d069",
        "libggml.0.dylib": "c04956f16207acec6b4f31b7edd9a15e433dde8b5fabed441c3465ba366a2866",
        "libllama.0.dylib": "a80faccd8d87e98994d07d0f595564deecb2bfd9a742465e195cc928c51f13df",
        "OLLAMA_LICENSE": "5934ed2ce0d15154bcdb9c85203210abac0da4314af34081e36df4599f90b226",
        "text-compat-provenance.json": "c69395898557d3cc11dac461585dc1b51f264ad2981721742ac2aef2db4685cb",
    }
    if any(info.get("runtime_sha256", {}).get(name) != expected for name, expected in pinned_members.items()):
        raise ValueError("Task runtime mathematical library or provenance differs from its pin")


def unique_keys(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("Duplicate runtime manifest key")
        value[key] = item
    return value


def main():
    source, destination = map(Path, sys.argv[1:])
    manifest = source / "build-manifest.json"
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 65536:
        raise ValueError("Missing bounded runtime build manifest")
    raw = manifest.read_bytes()
    info = json.loads(raw, object_pairs_hook=unique_keys)
    required = {
        "archi-gguf-shadow", "libllama.0.dylib", "libggml.0.dylib",
        "libggml-base.0.dylib", "libggml-cpu.0.dylib", "LICENSE", "JSON_LICENSE.MIT",
    }
    backend = info.get("backend_revision")
    if backend == "llama.cpp:161755f29+archi-qwen35-text-v1":
        validate_text_adapter(info)
        required.update({"OLLAMA_LICENSE", "text-compat-provenance.json"})
    elif backend != "llama.cpp:161755f29":
        raise ValueError("Unsupported representation backend")
    if (info.get("schema") != "archi-gguf-worker-build/v1"
            or info.get("upstream_revision") != "161755f29e415e2c33efe906e91843c068efd664"
            or info.get("architecture") != "arm64"
            or info.get("execution") != "cpu"
            or info.get("mode") != "shadow"
            or set(info.get("runtime_sha256", {})) != required):
        raise ValueError("Unsupported representation runtime identity or contents")
    for name in sorted(required):
        path = source / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 512 * 1024 * 1024:
            raise ValueError("Runtime member must be a bounded regular file: " + name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != info["runtime_sha256"][name]:
            raise ValueError("Runtime digest mismatch: " + name)
    destination.mkdir(parents=True, exist_ok=False)
    for name in sorted(required):
        shutil.copy2(source / name, destination / name)
        if hashlib.sha256((destination / name).read_bytes()).hexdigest() != info["runtime_sha256"][name]:
            raise ValueError("Copied runtime digest mismatch: " + name)
    (destination / manifest.name).write_bytes(raw)
    print("Packaged pinned arm64 read-only representation runtime")


if __name__ == "__main__":
    main()
