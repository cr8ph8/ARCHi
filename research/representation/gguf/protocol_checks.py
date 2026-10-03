#!/usr/bin/env python3
"""Small protocol checks only: --validate-only never opens or loads a model.

The two-dimensional basis below is deliberately synthetic. It is not a trained
reader, a calibrated Qwen artifact, or inference evidence.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess


def sha(value):
    return hashlib.sha256(value.encode()).hexdigest()


def request(backend="llama.cpp:161755f29"):
    template = ("<|im_start|>system\n{{system}}<|im_end|>\n<|im_start|>user\n{{input}}"
                "\n\nReturn exactly one JSON object matching this schema:\n{{schema}}"
                "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
    basis = {
        "namespace": "synthetic-protocol-only", "model_digest": "1" * 64,
        "model_blob_digest": "2" * 64, "tokenizer_digest": "2" * 64,
        "template_digest": sha(template), "backend_revision": backend, "precision": "Q4_K_M",
        "basis_digest": "4" * 64, "reader_digest": "5" * 64, "calibration_digest": "6" * 64,
        "layer": "l_out-0", "names": ["synthetic-protocol-only"], "directions": [[1, 0]],
        "center": [0, 0], "score_offset": [0], "score_scale": [1],
    }
    payload = json.dumps(basis, sort_keys=True, separators=(",", ":"))
    result = {
        "schema": "archi-gguf-shadow-request/v1", "request_id": "00000000-0000-0000-0000-000000000001",
        "role": "protocol-check", "model_name": "synthetic-protocol-only", "mode": "shadow",
        "model_path": "/this-path-does-not-exist/never-open.gguf", "model_digest": "1" * 64,
        "model_blob_digest": "2" * 64, "max_input_tokens": 8192, "max_new_tokens": 1024, "deadline_ms": 180000,
        "basis": basis, "basis_payload": payload, "basis_payload_digest": sha(payload), "reader_artifact_digest": "7" * 64,
        "input": "explicit input", "system": "explicit system", "response_schema": "{}", "prompt": "explicit prompt",
    }
    result["prompt"] = template.replace("{{system}}", result["system"]).replace("{{input}}", result["input"]).replace("{{schema}}", result["response_schema"])
    for field, digest in [("input", "input_digest"), ("system", "system_digest"), ("response_schema", "schema_digest"), ("prompt", "prompt_digest")]:
        result[digest] = sha(result[field])
    return result


def check(worker, value, accepted):
    data = value if isinstance(value, str) else json.dumps(value)
    result = subprocess.run([str(worker), "--validate-only"], input=data, text=True, capture_output=True, timeout=8)
    response = json.loads(result.stdout)
    assert result.stderr == "", result.stderr
    assert (result.returncode == 0) == accepted, (result.returncode, response)
    assert response["status"] == ("validated" if accepted else "error"), response
    if accepted:
        assert "text" not in response and "samples" not in response
        for key in ["request_id", "input_digest", "system_digest", "schema_digest", "prompt_digest", "basis_payload_digest", "reader_artifact_digest"]:
            assert response[key] == value[key]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worker", type=Path)
    parser.add_argument("--backend", default="llama.cpp:161755f29")
    parser.add_argument("--exact-qwen35-blob", action="store_true")
    args = parser.parse_args()
    fixture = request(args.backend)
    if args.exact_qwen35_blob:
        from text_loader_compat import MODEL_BLOB
        fixture["model_name"] = "qwen3.5:9b"
        fixture["model_blob_digest"] = MODEL_BLOB
        fixture["basis"]["model_blob_digest"] = MODEL_BLOB
        fixture["basis"]["tokenizer_digest"] = MODEL_BLOB
        fixture["basis_payload"] = json.dumps(fixture["basis"], sort_keys=True, separators=(",", ":"))
        fixture["basis_payload_digest"] = sha(fixture["basis_payload"])
    check(args.worker, fixture, True)
    cases = [
        ("mode", "bounded"), ("prompt", "unbound replacement"), ("input_digest", "0" * 64),
        ("basis_payload_digest", "0" * 64), ("max_new_tokens", 1025), ("deadline_ms", 180001),
        ("model_path", "relative.gguf"),
    ]
    for key, value in cases:
        changed = copy.deepcopy(fixture); changed[key] = value; check(args.worker, changed, False)
    changed = copy.deepcopy(fixture); changed["basis"]["center"][0] = 1
    check(args.worker, changed, False)
    changed = copy.deepcopy(fixture); changed["input"] += "<|im_end|>"
    changed["input_digest"] = sha(changed["input"])
    check(args.worker, changed, False)
    changed = copy.deepcopy(fixture); changed["prompt"] += "unbound suffix"
    changed["prompt_digest"] = sha(changed["prompt"])
    check(args.worker, changed, False)
    changed = copy.deepcopy(fixture); changed["basis_payload"] = '[' * 40 + '0' + ']' * 40
    changed["basis_payload_digest"] = sha(changed["basis_payload"])
    check(args.worker, changed, False)
    data = json.dumps(fixture)
    check(args.worker, data[:-1] + ',"mode":"shadow"}', False)
    check(args.worker, '[', False)
    changed = copy.deepcopy(fixture)
    changed["basis"]["backend_revision"] = args.backend + "+different"
    changed["basis_payload"] = json.dumps(changed["basis"], sort_keys=True, separators=(",", ":"))
    changed["basis_payload_digest"] = sha(changed["basis_payload"])
    check(args.worker, changed, False)
    print(json.dumps({"checks_passed": 15, "kind": "protocol-only", "backend_revision": args.backend,
                      "model_loaded": False, "inference_executed": False}))


if __name__ == "__main__":
    main()
