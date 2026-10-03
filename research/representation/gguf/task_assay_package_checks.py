#!/usr/bin/env python3
"""Focused packaging identity checks; copies output-local runtimes only."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[3]
SCRIPT = REPO / "script/package_representation_runtime.py"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--original-runtime", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("package_representation_runtime", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    info = json.loads((args.runtime / "build-manifest.json").read_bytes())
    cases = []
    module.validate_text_adapter(info)
    cases.append("exact-text-adapter-metadata")
    for key, replacement in [
        ("id", "unversioned"), ("model_blob_sha256", "0" * 64), ("alias_count", 23),
        ("model_bytes_modified", True), ("base_text_tensor_count", 428),
        ("excluded_auxiliary_tensors", {"vision": 441, "mtp": 16}),
    ]:
        value = copy.deepcopy(info); value["compatibility_patch"][key] = replacement
        try:
            module.validate_text_adapter(value)
        except ValueError:
            cases.append("reject-patch-" + key)
        else:
            raise AssertionError("Accepted altered patch: " + key)
    for key, replacement in [("reader_artifact_sha256", "0" * 64), ("max_new_tokens", 1),
                              ("measurement_scope", "general-replies"), ("layer", "l_out-15")]:
        value = copy.deepcopy(info); value["record_measurement"][key] = replacement
        try:
            module.validate_text_adapter(value)
        except ValueError:
            cases.append("reject-record-" + key)
        else:
            raise AssertionError("Accepted altered protocol: " + key)
    value = copy.deepcopy(info); value["runtime_sha256"]["libllama.0.dylib"] = "0" * 64
    try:
        module.validate_text_adapter(value)
    except ValueError:
        cases.append("reject-changed-mathematical-library")
    else:
        raise AssertionError("Accepted changed mathematical library")
    with tempfile.TemporaryDirectory(prefix="archi-record-package-") as temporary:
        root = Path(temporary)
        for name, runtime in [("record", args.runtime), ("original", args.original_runtime)]:
            destination = root / name
            proc = subprocess.run([sys.executable, str(SCRIPT), str(runtime), str(destination)],
                                  capture_output=True, text=True, timeout=15)
            assert proc.returncode == 0, proc.stderr
            manifest = json.loads((destination / "build-manifest.json").read_bytes())
            for member, expected in manifest["runtime_sha256"].items():
                assert hashlib.sha256((destination / member).read_bytes()).hexdigest() == expected
            cases.append("package-and-rehash-" + name)
        destination = root / "record"
        (destination / "libllama.0.dylib").write_bytes(b"altered copied test library")
        proc = subprocess.run([sys.executable, str(SCRIPT), str(destination), str(root / "rejected")],
                              capture_output=True, text=True, timeout=15)
        assert proc.returncode != 0 and not (root / "rejected").exists()
        cases.append("reject-tampered-member-before-copy")
    receipt = {"schema": "archi-record-package-checks/v1", "checksPassed": len(cases), "checks": cases,
               "packagerSHA256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
               "modelLoaded": False, "inferenceExecuted": False, "installedAppChanged": False}
    with args.receipt.open("x") as stream:
        json.dump(receipt, stream, indent=2); stream.write("\n")
    print(json.dumps({key: value for key, value in receipt.items() if key != "checks"}))


if __name__ == "__main__":
    main()
